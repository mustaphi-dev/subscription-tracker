import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

export const env = (k: string) => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};

export const admin: SupabaseClient = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** Cron calls carry the service key. */
export const isServiceCall = (req: Request) => {
  const key = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!key) return false;
  // Newer projects inject sb_secret_ keys here and in SUPABASE_SECRET_KEYS; accept either kind.
  const secrets = Object.values(JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"));
  return key === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || secrets.includes(key);
};

/** Resolve the signed-in user from the app's JWT, or null. */
export async function userFrom(req: Request): Promise<string | null> {
  const jwt = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt);
  return data.user?.id ?? null;
}

// ───────── FCM HTTP v1 ─────────
let fcmToken: { value: string; exp: number } | null = null;

async function fcmAccessToken(sa: { client_email: string; private_key: string }) {
  if (fcmToken && fcmToken.exp > Date.now() + 60_000) return fcmToken.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email).setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt().setExpirationTime("1h").sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const { access_token, expires_in } = await res.json();
  fcmToken = { value: access_token, exp: Date.now() + expires_in * 1000 };
  return access_token;
}

export async function sendPush(token: string, title: string, body: string, data: Record<string, string> = {}) {
  const sa = JSON.parse(env("FCM_SERVICE_ACCOUNT"));
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${await fcmAccessToken(sa)}`, "content-type": "application/json" },
    body: JSON.stringify({
      message: {
        token, notification: { title, body }, data,
        apns: { payload: { aps: { sound: "default", category: data.type ?? "" } } },
        android: { priority: "high", notification: { channel_id: "alerts" } },
      },
    }),
  });
  if (!res.ok) console.error("fcm", res.status, await res.text());
  return res.ok;
}

export const money = (n: number, ccy = "GBP") =>
  new Intl.NumberFormat("en-GB", { style: "currency", currency: ccy }).format(n);
