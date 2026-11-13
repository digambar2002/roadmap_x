// Gemini proxy for Premium users.
//
// The app sends { model, request } with the user's Supabase session token.
// This function checks the user is signed in and Premium, enforces a daily
// per-user cap, then forwards the request to Gemini with the project's own
// key (never shipped in the app) and returns Google's reply unchanged, so the
// app parses it exactly like a direct call.
//
// Deploy:
//   supabase secrets set GEMINI_API_KEY=your-key
//   supabase functions deploy gemini
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_MODELS = new Set(["gemini-3.8-flash", "gemini-3.1-pro-preview"]);
const DEFAULT_MODEL = "gemini-3.8-flash";
const DAILY_CAP = Number(Deno.env.get("AI_DAILY_CAP") ?? "60");

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
  if (premiumError || premium !== true) {
    return geminiError(403, "PERMISSION_DENIED", "AI is part of RoadmapX Premium.");
  }

  // Atomic per-user daily counter; refuses past the cap.
  const { data: used, error: usageError } = await supabase.rpc("use_ai_request", { cap: DAILY_CAP });
  if (usageError) return geminiError(500, "INTERNAL", "Could not check AI usage.");
  if (used === -1) {
    return geminiError(429, "RESOURCE_EXHAUSTED",
      `Daily AI limit of ${DAILY_CAP} requests reached. It resets at midnight UTC.`,
      [{ "@type": "type.googleapis.com/google.rpc.QuotaFailure", quotaId: "RoadmapXRequestsPerDay" }]);
  }

  let body: { model?: string; request?: unknown };
  try {
    body = await req.json();
  } catch {
    return geminiError(400, "INVALID_ARGUMENT", "Body must be JSON.");
  }
  const model = ALLOWED_MODELS.has(body.model ?? "") ? body.model! : DEFAULT_MODEL;
  if (typeof body.request !== "object" || body.request === null) {
    return geminiError(400, "INVALID_ARGUMENT", "Missing request.");
  }

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return geminiError(500, "INTERNAL", "AI is not configured on the server.");

  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify(body.request),
    },
  );
  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
});
