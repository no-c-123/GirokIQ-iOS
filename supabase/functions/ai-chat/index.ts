import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const anthropicURL = "https://api.anthropic.com/v1/messages";
const defaultModel = "claude-sonnet-4-6";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const anthropicAPIKey = Deno.env.get("ANTHROPIC_API_KEY");

  if (!supabaseURL || !supabaseAnonKey || !anthropicAPIKey) {
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

  const anthropicPayload = {
    ...payload,
    model: typeof payload.model === "string" && payload.model.length > 0
      ? payload.model
      : defaultModel,
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
