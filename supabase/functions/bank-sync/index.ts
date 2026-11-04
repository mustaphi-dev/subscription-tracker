// Open Banking via GoCardless Bank Account Data (covers Lloyds, Revolut, Wise and PayPal).
// Routes: POST /connect (user), GET /callback (browser redirect), POST /sync (user), POST /sync-all (cron).
import { admin, env, isServiceCall, json, money, sendPush, userFrom } from "../_shared/mod.ts";

const GC = "https://bankaccountdata.gocardless.com/api/v2";
const INSTITUTIONS: Record<string, string> = {
  lloyds: "LLOYDS_LOYDGB2L",
  revolut: "REVOLUT_REVOGB21",
  wise: "WISE_TRWIGB22",
  paypal: "PAYPAL_PPLXLULL",
};

let gcToken: { value: string; exp: number } | null = null;
async function gc(path: string, init: RequestInit = {}) {
  if (!gcToken || gcToken.exp < Date.now() + 60_000) {
    const r = await fetch(`${GC}/token/new/`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ secret_id: env("GOCARDLESS_SECRET_ID"), secret_key: env("GOCARDLESS_SECRET_KEY") }),
    }).then((r) => r.json());
    gcToken = { value: r.access, exp: Date.now() + r.access_expires * 1000 };
  }
  const res = await fetch(`${GC}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${gcToken.value}`, "content-type": "application/json", ...init.headers },
  });
  if (!res.ok) throw new Error(`gocardless ${path} ${res.status}: ${await res.text()}`);
  return res.json();
}

Deno.serve(async (req) => {
  const route = new URL(req.url).pathname.split("/").pop();
  try {
    if (route === "connect") return await connect(req);
    if (route === "callback") return await callback(req);
    if (route === "sync") {
      const uid = await userFrom(req);
      if (!uid) return json({ error: "unauthorised" }, 401);
      return json(await syncUser(uid));
    }
    if (route === "sync-all") {
      if (!isServiceCall(req)) return json({ error: "forbidden" }, 403);
      const { data } = await admin.from("bank_connections").select("user_id").eq("status", "linked");
      for (const uid of new Set((data ?? []).map((c) => c.user_id))) await syncUser(uid).catch(console.error);
      return json({ ok: true });
    }
    return json({ error: "not found" }, 404);
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

async function connect(req: Request) {
  const uid = await userFrom(req);
  if (!uid) return json({ error: "unauthorised" }, 401);
  const { provider } = await req.json();
  const institution_id = INSTITUTIONS[provider];
  if (!institution_id) return json({ error: "unknown provider" }, 400);

  const reference = crypto.randomUUID();
  const reqn = await gc("/requisitions/", {
    method: "POST",
    body: JSON.stringify({
      institution_id, reference, user_language: "EN",
      redirect: `${env("SUPABASE_URL")}/functions/v1/bank-sync/callback`,
    }),
  });
  await admin.from("bank_connections").insert({ user_id: uid, provider, reference, requisition_id: reqn.id });
  return json({ link: reqn.link });
}

async function callback(req: Request) {
  const ref = new URL(req.url).searchParams.get("ref");
  const { data: conn } = await admin.from("bank_connections").select().eq("reference", ref).eq("status", "pending").single();
  if (!conn) return new Response("Unknown or used link", { status: 400 });
  await admin.from("bank_connections").update({ status: "linked" }).eq("id", conn.id);
  await syncUser(conn.user_id).catch(console.error);
  return Response.redirect("subtracker://bank-connected", 302);
}

async function syncUser(uid: string) {
  const { data: conns } = await admin.from("bank_connections").select().eq("user_id", uid).eq("status", "linked");
  let accounts = 0;
  for (const conn of conns ?? []) {
    const reqn = await gc(`/requisitions/${conn.requisition_id}/`);
    if (reqn.status === "EX" || reqn.status === "RJ") {
      await admin.from("bank_connections").update({ status: "expired" }).eq("id", conn.id);
      continue;
    }
    for (const accId of reqn.accounts as string[]) {
      await syncAccount(uid, conn.provider, accId);
      accounts++;
    }
  }
  return { accounts };
}

// ponytail: GoCardless rate-limits to ~4 calls/account/endpoint/day; cron runs every 6h to fit.
async function syncAccount(uid: string, provider: string, accId: string) {
  const [{ account }, { balances }, { transactions }] = await Promise.all([
    gc(`/accounts/${accId}/details/`),
    gc(`/accounts/${accId}/balances/`),
    gc(`/accounts/${accId}/transactions/`),
  ]);
  const bal = balances.find((b: any) => b.balanceType === "interimAvailable") ?? balances[0];
  const { data: source } = await admin.from("payment_sources").upsert({
    user_id: uid, provider, external_account_id: accId,
    account_name: account.name ?? account.ownerName ?? `${provider} ${bal.balanceAmount.currency}`,
    current_balance: Number(bal.balanceAmount.amount),
    currency: bal.balanceAmount.currency,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "user_id,external_account_id" }).select().single();

  const { data: existing } = await admin.from("financial_items").select("merchant_name").eq("user_id", uid);
  const known = new Set((existing ?? []).map((i) => norm(i.merchant_name)));

  await detectCardChecks(uid, source!.id, transactions.pending ?? [], known);
  await detectRecurring(uid, source!.id, transactions.booked ?? [], known);
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z ]/g, "").replace(/\s+/g, " ").trim();
const merchantOf = (t: any) => t.creditorName ?? t.remittanceInformationUnstructured ?? "Unknown";
const amountOf = (t: any) => Number(t.transactionAmount.amount);

/** £0.00 / £1.00 pending authorisations from an unknown merchant = probable free-trial card check. */
async function detectCardChecks(uid: string, sourceId: string, pending: any[], known: Set<string>) {
  for (const t of pending) {
    const amt = amountOf(t);
    if (amt > 0 || amt < -1) continue;
    const name = merchantOf(t);
    if (known.has(norm(name))) continue;
    known.add(norm(name));

    const { data: prices } = await admin.from("merchant_prices").select();
    const price = prices?.find((p) => norm(name).includes(p.merchant_key));
    const trialEnd = new Date(Date.now() + 7 * 864e5); // ponytail: assume 7-day trial until user confirms
    const { data: item } = await admin.from("financial_items").insert({
      user_id: uid, payment_source_id: sourceId, item_type: "free_trial", merchant_name: name,
      original_amount: 0, original_currency: price?.currency ?? t.transactionAmount.currency,
      post_trial_amount: price?.amount ?? null, billing_cycle: price?.billing_cycle ?? "monthly",
      cancellation_url: price?.cancellation_url ?? null, trial_end_date: trialEnd.toISOString(),
      status: "pending_confirmation", auto_detected_via: "open_banking",
    }).select().single();

    const { data: profile } = await admin.from("profiles").select("fcm_token").eq("id", uid).single();
    if (profile?.fcm_token && item) {
      const est = price ? ` Likely ${money(price.amount, price.currency)}/${price.billing_cycle} after.` : "";
      await sendPush(profile.fcm_token, `New trial detected: ${name}?`,
        `We saw a card check from ${name}.${est} Tap to confirm the trial details.`,
        { type: "confirm_trial", item_id: item.id });
      await admin.from("alert_logs").insert({ financial_item_id: item.id, alert_stage: "confirm_trial" });
    }
  }
}

/** ≥2 debits to the same merchant, similar amount, ~monthly apart = subscription. */
async function detectRecurring(uid: string, sourceId: string, booked: any[], known: Set<string>) {
  const groups = new Map<string, any[]>();
  for (const t of booked) {
    if (amountOf(t) >= 0) continue;
    const k = norm(merchantOf(t));
    if (!known.has(k)) groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  for (const txs of groups.values()) {
    if (txs.length < 2) continue;
    txs.sort((a, b) => a.bookingDate.localeCompare(b.bookingDate));
    const [prev, last] = txs.slice(-2);
    const gapDays = (Date.parse(last.bookingDate) - Date.parse(prev.bookingDate)) / 864e5;
    const sameAmount = Math.abs(amountOf(last) - amountOf(prev)) <= Math.abs(amountOf(prev)) * 0.1;
    if (gapDays < 25 || gapDays > 35 || !sameAmount) continue;

    const next = new Date(last.bookingDate);
    next.setMonth(next.getMonth() + 1);
    await admin.from("financial_items").insert({
      user_id: uid, payment_source_id: sourceId, item_type: "subscription",
      merchant_name: merchantOf(last), original_amount: Math.abs(amountOf(last)),
      original_currency: last.transactionAmount.currency, billing_cycle: "monthly",
      next_renewal_date: next.toISOString().slice(0, 10), auto_detected_via: "open_banking",
      total_spent: txs.reduce((s, t) => s + Math.abs(amountOf(t)), 0),
    });
  }
}
