import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library";

type SubscriptionTier = "free" | "pro";

const subscriptionProductIDs = new Set([
  "com.girokiq.pro.monthly",
  "com.girokiq.pro.annual",
]);

const appleRootCertURLs = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];

let appleRootCertsPromise: Promise<Buffer[]> | null = null;
function loadAppleRootCertificates(): Promise<Buffer[]> {
  if (appleRootCertsPromise) return appleRootCertsPromise;

  appleRootCertsPromise = Promise.all(
    appleRootCertURLs.map(async (url) => {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Failed to fetch Apple root cert: ${url}`);
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      return Buffer.from(bytes);
    }),
  );

  return appleRootCertsPromise;
}

async function verifyTransaction(
  signedTransactionInfo: string,
  bundleId: string,
  appAppleId?: number,
): Promise<{
  tier: SubscriptionTier;
  decodedProductId?: string;
  decodedAppAccountToken?: string;
}> {
  const roots = await loadAppleRootCertificates();

  // StoreKit can produce transactions for different environments:
  // - Xcode / LocalTesting when using a `.storekit` configuration
  // - Sandbox for TestFlight / sandbox testers
  // - Production for real purchases
  //
  // We attempt multiple environments because the verifier rejects mismatches.
  const attempts: Array<{ env: Environment; allowOnlineChecks: boolean }> = [
    { env: Environment.XCODE, allowOnlineChecks: false },
    { env: Environment.LOCAL_TESTING, allowOnlineChecks: false },
    { env: Environment.SANDBOX, allowOnlineChecks: true },
    { env: Environment.PRODUCTION, allowOnlineChecks: true },
  ];

  let lastError: unknown = null;
  for (const attempt of attempts) {
    try {
      const verifier = new SignedDataVerifier(
        roots,
        attempt.allowOnlineChecks,
        attempt.env,
        bundleId,
        attempt.env === Environment.PRODUCTION ? appAppleId : undefined,
      );

      const decoded = await verifier.verifyAndDecodeTransaction(
        signedTransactionInfo,
      );

      return {
        tier: resolveTier(decoded),
        decodedProductId: decoded.productId,
        decodedAppAccountToken: decoded.appAccountToken,
      };
    } catch (error) {
      lastError = error;
      console.warn(
        "[verify-subscription] Transaction verification failed for env",
        attempt.env,
        error,
      );
    }
  }

  throw lastError ?? new Error("Transaction verification failed.");
}

function resolveTier(decoded: { productId?: string; expiresDate?: number; revocationDate?: number }): SubscriptionTier {
  const productId = decoded.productId;
  if (!productId || !subscriptionProductIDs.has(productId)) return "free";
  if (typeof decoded.revocationDate === "number" && decoded.revocationDate > 0) return "free";
  if (typeof decoded.expiresDate === "number" && decoded.expiresDate <= Date.now()) return "free";
  return "pro";
}

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
  const appleBundleId = Deno.env.get("APPLE_BUNDLE_ID");
  const appleAppId = Deno.env.get("APPLE_APP_ID");

  if (!supabaseURL || !supabaseAnonKey || !supabaseServiceRoleKey || !appleBundleId) {
    return jsonResponse({ error: "Missing required environment variables." }, 500);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header." }, 401);
  }

  const supabase = createClient(supabaseURL, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await request.json();
  } catch {
    // allow empty body
  }

  const signedTransactionInfo = typeof payload.transaction_jws === "string"
    ? payload.transaction_jws
    : typeof payload.jwsRepresentation === "string"
    ? payload.jwsRepresentation
    : null;

  let tier: SubscriptionTier = "free";
  let decodedProductId: string | undefined;
  let decodedAppAccountToken: string | undefined;
  let downgradeReason: string | null = null;

  if (signedTransactionInfo) {
    try {
      const appIdNumber = appleAppId ? Number(appleAppId) : undefined;
      const verified = await verifyTransaction(
        signedTransactionInfo,
        appleBundleId,
        Number.isFinite(appIdNumber) ? appIdNumber : undefined,
      );
      tier = verified.tier;
      decodedProductId = verified.decodedProductId;
      decodedAppAccountToken = verified.decodedAppAccountToken;
    } catch (error) {
      console.error("[verify-subscription] JWS verification failed", error);
      tier = "free";
    }
  }

  // Bind subscription entitlement to the authenticated Supabase user.
  // Prevent replaying a valid JWS from one account onto another.
  if (tier === "pro") {
    const expected = user.id.toLowerCase();
    const actual = (decodedAppAccountToken ?? "").toLowerCase();
    if (!actual || actual !== expected) {
      console.warn(
        "[verify-subscription] appAccountToken mismatch; downgrading to free",
        { expected, actual },
      );
      tier = "free";
      downgradeReason = "app_account_token_mismatch";
      // Hide product id when we're refusing to grant entitlement, to avoid confusing
      // client logs/UI in multi-account testing.
      decodedProductId = undefined;
    }
  }

  const adminSupabase = createClient(supabaseURL, supabaseServiceRoleKey);
  const { error: writeError } = await adminSupabase
    .from("app_state")
    .upsert({
      user_id: user.id,
      subscription_tier: tier,
      updated_at: new Date().toISOString(),
    });

  if (writeError) {
    console.error("[verify-subscription] Failed to write subscription tier", writeError);
    return jsonResponse({ error: "Failed to persist subscription tier." }, 500);
  }

  return jsonResponse(
    {
      subscription_tier: tier,
      product_id: decodedProductId ?? null,
      reason: downgradeReason,
    },
    200,
  );
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
