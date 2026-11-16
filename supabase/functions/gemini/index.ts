// Gemini proxy for signed-in users.
//
// The app sends { model, request } with the user's Supabase session token.
// This function checks the user is signed in, then applies a limit:
//   - Premium: AI_DAILY_CAP requests a day (default 60), any allowed model.
//   - Free:    AI_FREE_MONTHLY_CAP requests a month (default 3), which the
//              app spends on AI-built plans. Always the Flash model. A
//              request Gemini fails is given back.
// It then forwards the request to Gemini with the project's own key (never
// shipped in the app) and returns Google's reply unchanged, so the app
// parses it exactly like a direct call.
//
// Deploy:
//   supabase secrets set GEMINI_API_KEY=your-key
//   supabase functions deploy gemini
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_MODELS = new Set(["gemini-3.8-flash", "gemini-3.1-pro-preview"]);
const DEFAULT_MODEL = "gemini-3.8-flash";
const DAILY_CAP = Number(Deno.env.get("AI_DAILY_CAP") ?? "60");
// Keep in step with Entitlements.freeAiPlansPerMonth in the app.
const FREE_MONTHLY_CAP = Number(Deno.env.get("AI_FREE_MONTHLY_CAP") ?? "3");

function geminiError(code: number, status: string, message: string, details: unknown[] = []) {
  // Same shape as Google's errors, so the app's handling is identical.
  return new Response(
    JSON.stringify({ error: { code, status, message, details } }),
    { status: code, headers: { "Content-Type": "application/json" } },
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return geminiError(405, "INVALID_ARGUMENT", "Use POST.");

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return geminiError(401, "UNAUTHENTICATED", "Sign in to use AI.");
  }

  // A client acting as the caller: RLS and auth.uid() apply.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return geminiError(401, "UNAUTHENTICATED", "Session expired. Sign in again.");

  const { data: premium, error: premiumError } = await supabase.rpc("is_premium", { uid: user.id });
  if (premiumError) return geminiError(500, "INTERNAL", "Could not check your plan.");
  const isPremium = premium === true;

  // Atomic per-user counters; each refuses past its cap.
  if (isPremium) {
    const { data: used, error: usageError } = await supabase.rpc("use_ai_request", { cap: DAILY_CAP });
    if (usageError) return geminiError(500, "INTERNAL", "Could not check AI usage.");
    if (used === -1) {
      return geminiError(429, "RESOURCE_EXHAUSTED",
        `Daily AI limit of ${DAILY_CAP} requests reached. It resets at midnight UTC.`,
        [{ "@type": "type.googleapis.com/google.rpc.QuotaFailure", quotaId: "RoadmapXRequestsPerDay" }]);
    }
  } else {
    const { data: used, error: usageError } = await supabase.rpc("use_free_ai_request", { cap: FREE_MONTHLY_CAP });
    if (usageError) return geminiError(500, "INTERNAL", "Could not check AI usage.");
    if (used === -1) {
      return geminiError(429, "RESOURCE_EXHAUSTED",
        `This month's ${FREE_MONTHLY_CAP} free AI plans are used. They renew on the 1st.`,
        [{ "@type": "type.googleapis.com/google.rpc.QuotaFailure", quotaId: "RoadmapXFreePlansPerMonth" }]);
    }
  }

  // A free request that never reaches a good answer is handed back.
  const refund = async () => {
    if (isPremium) return;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return;
    try {
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
      await admin.rpc("refund_ai_request", { target: user.id });
    } catch (_) { /* a missed refund must not hide the real error */ }
  };

  let body: { model?: string; request?: unknown };
  try {
    body = await req.json();
  } catch {
    await refund();
    return geminiError(400, "INVALID_ARGUMENT", "Body must be JSON.");
  }
  // Free plans always use Flash; Premium may pick any allowed model.
  const model = isPremium && ALLOWED_MODELS.has(body.model ?? "") ? body.model! : DEFAULT_MODEL;
  if (typeof body.request !== "object" || body.request === null) {
    await refund();
    return geminiError(400, "INVALID_ARGUMENT", "Missing request.");
  }

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) {
    await refund();
    return geminiError(500, "INTERNAL", "AI is not configured on the server.");
  }

  let upstream: Response;
  try {
    upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify(body.request),
      },
    );
  } catch (_) {
    await refund();
    return geminiError(503, "UNAVAILABLE", "Could not reach Gemini. Try again.");
  }
  if (!upstream.ok) await refund();
  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
});
