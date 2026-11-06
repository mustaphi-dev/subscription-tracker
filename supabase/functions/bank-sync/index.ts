// Open Banking account linking. The provider for each country lives in ./aggregators.
// Routes: POST /connect (user), GET /callback (browser redirect), POST /sync (user), POST /sync-all (cron).
import { admin, env, isServiceCall, json, money, sendPush, userFrom } from "../_shared/mod.ts";
import { gocardless } from "./aggregators/gocardless.ts";
import type { Aggregator, Txn } from "./aggregators/types.ts";

const AGGREGATORS: Aggregator[] = [gocardless];
const byId = (id: string) => AGGREGATORS.find((a) => a.id === id);
const forCountry = (c: string | null) => AGGREGATORS.find((a) => c != null && a.countries.includes(c));

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
    // Provider errors can carry ids and internals; log them, don't hand them to the app.
    console.error(e);
    return json({ error: "Something went wrong talking to your bank. Try again in a minute." }, 500);
  }
});

async function connect(req: Request) {
  const uid = await userFrom(req);
  if (!uid) return json({ error: "unauthorised" }, 401);
  const { provider } = await req.json();

  const { data: profile } = await admin.from("profiles").select("country").eq("id", uid).single();
  const agg = forCountry(profile?.country ?? null);
  if (!agg) return json({ error: "Automatic bank sync isn't available in your country yet. You can add accounts manually." }, 400);
  if (!agg.institutions.includes(provider)) return json({ error: "unknown provider" }, 400);

  const reference = crypto.randomUUID();
  const { externalId, link } = await agg.createLink({
    institution: provider, reference,
    redirect: `${env("SUPABASE_URL")}/functions/v1/bank-sync/callback`,
  });
  await admin.from("bank_connections").insert({ user_id: uid, provider, reference, aggregator: agg.id, external_id: externalId });
  return json({ link });
}

async function callback(req: Request) {
  const q = new URL(req.url).searchParams;
  const ref = q.get("ref") ?? q.get("state");
  const { data: conn } = await admin.from("bank_connections").select().eq("reference", ref).eq("status", "pending").maybeSingle();
  if (!conn) return new Response("Unknown or used link", { status: 400 });

  // The redirect fires whether or not the user approved, so ask the provider what actually happened.
  const { status } = await byId(conn.aggregator)!.status(conn.external_id);
  if (status !== "linked") {
    if (status !== "pending") await admin.from("bank_connections").update({ status }).eq("id", conn.id);
    return Response.redirect("subtracker://bank-connected?status=failed", 302);
  }
  await admin.from("bank_connections").update({ status: "linked" }).eq("id", conn.id);
  await syncUser(conn.user_id).catch(console.error);
  return Response.redirect("subtracker://bank-connected", 302);
}

async function syncUser(uid: string) {
  const { data: conns } = await admin.from("bank_connections").select().eq("user_id", uid).eq("status", "linked");
  let accounts = 0;
  for (const conn of conns ?? []) {
    const agg = byId(conn.aggregator);
    if (!agg) continue;
    const s = await agg.status(conn.external_id);
    if (s.status === "expired" || s.status === "rejected") {
      await admin.from("bank_connections").update({ status: "expired" }).eq("id", conn.id);
      continue;
    }
    for (const accId of s.accounts) {
      await syncAccount(uid, agg, conn.provider, accId);
      accounts++;
    }
  }
  return { accounts };
}

async function syncAccount(uid: string, agg: Aggregator, provider: string, accId: string) {
  const { account, transactions } = await agg.fetchAccount(accId);
  const { data: source } = await admin.from("payment_sources").upsert({
    user_id: uid, provider, external_account_id: accId,
    account_name: account.name,
    current_balance: account.balance,
    currency: account.currency,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "user_id,external_account_id" }).select().single();

  const { data: existing } = await admin.from("financial_items").select("merchant_name").eq("user_id", uid);
  const known = new Set((existing ?? []).map((i) => norm(i.merchant_name)));

  await detectCardChecks(uid, source!.id, transactions.filter((t) => t.pending), known);
  await detectRecurring(uid, source!.id, transactions.filter((t) => !t.pending), known);
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z ]/g, "").replace(/\s+/g, " ").trim();

/** £0.00 / £1.00 pending authorisations from an unknown merchant = probable free-trial card check. */
async function detectCardChecks(uid: string, sourceId: string, pending: Txn[], known: Set<string>) {
  for (const t of pending) {
    const amt = t.amount;
    if (amt > 0 || amt < -1) continue;
    const name = t.merchant;
    if (known.has(norm(name))) continue;
    known.add(norm(name));

    const { data: prices } = await admin.from("merchant_prices").select();
    const price = prices?.find((p) => norm(name).includes(p.merchant_key));
    const trialEnd = new Date(Date.now() + 7 * 864e5); // ponytail: assume 7-day trial until user confirms
    const { data: item } = await admin.from("financial_items").insert({
      user_id: uid, payment_source_id: sourceId, item_type: "free_trial", merchant_name: name,
      original_amount: 0, original_currency: price?.currency ?? t.currency,
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
async function detectRecurring(uid: string, sourceId: string, booked: Txn[], known: Set<string>) {
  const groups = new Map<string, Txn[]>();
  for (const t of booked) {
    if (t.amount >= 0) continue;
    const k = norm(t.merchant);
    if (!known.has(k)) groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  for (const txs of groups.values()) {
    if (txs.length < 2) continue;
    txs.sort((a, b) => a.date.localeCompare(b.date));
    const [prev, last] = txs.slice(-2);
    const gapDays = (Date.parse(last.date) - Date.parse(prev.date)) / 864e5;
    const sameAmount = Math.abs(last.amount - prev.amount) <= Math.abs(prev.amount) * 0.1;
    if (gapDays < 25 || gapDays > 35 || !sameAmount) continue;

    const next = new Date(last.date);
    next.setMonth(next.getMonth() + 1);
    await admin.from("financial_items").insert({
      user_id: uid, payment_source_id: sourceId, item_type: "subscription",
      merchant_name: last.merchant, original_amount: Math.abs(last.amount),
      original_currency: last.currency, billing_cycle: "monthly",
      next_renewal_date: next.toISOString().slice(0, 10), auto_detected_via: "open_banking",
      total_spent: txs.reduce((s, t) => s + Math.abs(t.amount), 0),
    });
  }
}
