import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const anthropicURL = "https://api.anthropic.com/v1/messages";
const proModel = "claude-sonnet-4-6";
const freeModel = "claude-haiku-4-5";
const freeTierDailyRequestLimit = 10;
const freeTierMaxTokens = 1200;
type SubscriptionTier = "free" | "pro";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const supabaseServiceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anthropicAPIKey = Deno.env.get("ANTHROPIC_API_KEY");

  if (!supabaseURL || !supabaseAnonKey || !supabaseServiceRoleKey || !anthropicAPIKey) {
    return jsonResponse({ error: "Missing required environment variables." }, 500);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header." }, 401);
  }

  const supabase = createClient(supabaseURL, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });

  // Service role client used for writes that must not be possible from a user JWT.
  // This bypasses RLS and column privileges, so keep it strictly scoped.
  const adminSupabase = createClient(supabaseURL, supabaseServiceRoleKey);

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }

  const messages = payload.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return jsonResponse({ error: "At least one message is required." }, 400);
  }

  const subscriptionTier = await fetchSubscriptionTier(supabase, user.id);

  if (subscriptionTier === "free") {
    // Fail closed for free tier: reserve a slot before calling Anthropic so we
    // always enforce limits even if the downstream call succeeds but tracking fails.
    const nextCount = await reserveDailyUsageCount(adminSupabase, user.id);
    if (nextCount === null) {
      return jsonResponse(
        { error: "AI usage tracking failed. Please try again in a moment." },
        500,
      );
    }

    if (nextCount > freeTierDailyRequestLimit) {
      return jsonResponse(
        {
          error: `Free plan AI limit reached for today. You can send up to ${freeTierDailyRequestLimit} AI requests per day on the free plan. Upgrade to Pro for higher limits.`,
          code: "free_ai_limit_reached",
          subscription_tier: subscriptionTier,
          daily_request_limit: freeTierDailyRequestLimit,
          daily_request_count: nextCount,
        },
        429,
      );
    }
  }

  const anthropicPayload = {
    ...payload,
    model: resolveModel(subscriptionTier),
    max_tokens: resolveMaxTokens(payload.max_tokens, subscriptionTier),
  };

  const anthropicResponse = await fetch(anthropicURL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": anthropicAPIKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(anthropicPayload),
  });

  if (payload.stream === true && anthropicResponse.body) {
    return new Response(anthropicResponse.body, {
      status: anthropicResponse.status,
      headers: {
        ...corsHeaders,
        "Content-Type": anthropicResponse.headers.get("Content-Type") ?? "text/event-stream",
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
      },
    });
  }

  const responseText = await anthropicResponse.text();
  return new Response(responseText, {
    status: anthropicResponse.status,
    headers: {
      ...corsHeaders,
      "Content-Type": anthropicResponse.headers.get("Content-Type") ?? "application/json",
    },
  });
});

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function fetchSubscriptionTier(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<SubscriptionTier> {
  const { data, error } = await supabase
    .from("app_state")
    .select("subscription_tier")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    console.error("[ai-chat] Failed to read subscription tier", error);
    return "free";
  }

  return data?.subscription_tier === "pro" ? "pro" : "free";
}

async function fetchDailyUsageCount(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<number> {
  const usageDate = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("ai_usage_daily")
    .select("request_count")
    .eq("user_id", userId)
    .eq("usage_date", usageDate)
    .maybeSingle();

  if (error) {
    console.error("[ai-chat] Failed to read daily AI usage", error);
    return 0;
  }

  return typeof data?.request_count === "number" ? data.request_count : 0;
}

async function reserveDailyUsageCount(
  adminSupabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<number | null> {
  const { data, error } = await adminSupabase.rpc("increment_ai_usage_daily", {
    p_user_id: userId,
  });

  if (error) {
    console.error("[ai-chat] Failed to increment daily AI usage", error);
    return null;
  }

  return typeof data === "number" ? data : null;
}

function resolveModel(subscriptionTier: SubscriptionTier): string {
  return subscriptionTier === "pro" ? proModel : freeModel;
}

function resolveMaxTokens(value: unknown, subscriptionTier: SubscriptionTier): number {
  const requested = typeof value === "number" && Number.isFinite(value)
    ? Math.floor(value)
    : 4096;

  if (subscriptionTier === "pro") {
    return Math.max(256, Math.min(requested, 4096));
  }

  return Math.max(256, Math.min(requested, freeTierMaxTokens));
}
