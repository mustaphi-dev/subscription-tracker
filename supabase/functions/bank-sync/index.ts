// Open Banking account linking. The provider for each country lives in ./aggregators.
// Routes: POST /banks, POST /connect, POST /sync, POST /disconnect (user); GET /callback (browser redirect); POST /sync-all (cron).
import { admin, env, isServiceCall, json, money, sendPush, userFrom } from "../_shared/mod.ts";
import { trueLayer } from "./aggregators/truelayer.ts";
import type { Txn } from "./aggregators/types.ts";
import { norm, recurring } from "./detect.ts";
import { dbTokens } from "./tokens.ts";

const callbackUrl = () => `${env("SUPABASE_URL")}/functions/v1/bank-sync/callback`;

Deno.serve(async (req) => {
  const route = new URL(req.url).pathname.split("/").pop();
  try {
    if (route === "banks") return await banks(req);
    if (route === "connect") return await connect(req);
    if (route === "disconnect") return await disconnect(req);
    if (route === "callback") return await callback(req);
    if (route === "sync") {
      const uid = await userFrom(req);
      if (!uid) return json({ error: "unauthorised" }, 401);
      return json(await syncUser(uid));
    }
    if (route === "sync-all") {
      if (!isServiceCall(req)) return json({ error: "forbidden" }, 403);
      const { data } = await admin().from("bank_connections").select("user_id").eq("status", "linked");
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

async function userAggregator(uid: string) {
  const { data: profile } = await admin().from("profiles").select("country").eq("id", uid).single();
  const country: string | null = profile?.country ?? null;
  return { country, agg: country && trueLayer.countries.includes(country) ? trueLayer : null };
}

const UNAVAILABLE = "Automatic bank sync isn't available in your country yet. You can add accounts manually.";

async function banks(req: Request) {
  const uid = await userFrom(req);
  if (!uid) return json({ error: "unauthorised" }, 401);
  const { country, agg } = await userAggregator(uid);
  if (!agg) return json({ error: UNAVAILABLE }, 400);
  return json({ banks: await agg.listBanks(country!) });
}

async function connect(req: Request) {
  const uid = await userFrom(req);
  if (!uid) return json({ error: "unauthorised" }, 401);
  const { bank } = await req.json();
  const { country, agg } = await userAggregator(uid);
  if (!agg) return json({ error: UNAVAILABLE }, 400);
  if (!(await agg.listBanks(country!)).some((b) => b.name === bank)) return json({ error: "unknown bank" }, 400);

  const reference = crypto.randomUUID();
  const { externalId, link } = await agg.createLink({
    bank, country: country!, reference, redirect: callbackUrl(),
  });
  // `provider` holds the bank's display name for links made from here on.
  await admin().from("bank_connections").insert({ user_id: uid, provider: bank, reference, aggregator: agg.id, external_id: externalId });
  return json({ link });
}

/** Unlinks a bank: drops its consents, stored tokens and synced accounts. Tracked items stay, detached. */
async function disconnect(req: Request) {
  const uid = await userFrom(req);
  if (!uid) return json({ error: "unauthorised" }, 401);
  const { bank } = await req.json();
  if (typeof bank !== "string" || !bank) return json({ error: "bank required" }, 400);
  // ponytail: forgets the link on our side only; the bank's consent lapses on its own (90 days max).
  const { data: conns } = await admin().from("bank_connections").select("external_id").eq("user_id", uid).eq("provider", bank);
  const ids = (conns ?? []).map((c) => c.external_id).filter(Boolean);
  for (const id of ids) await dbTokens.remove(id);
  for (const r of [
    await admin().from("bank_connections").delete().eq("user_id", uid).eq("provider", bank),
    await admin().from("payment_sources").delete().eq("user_id", uid).eq("institution", bank).eq("is_manual", false),
  ]) if (r.error) throw r.error;
  return json({ ok: true });
}

async function callback(req: Request) {
  const q = new URL(req.url).searchParams;
  const ref = q.get("ref") ?? q.get("state");
  const { data: conn } = await admin().from("bank_connections").select().eq("reference", ref).eq("status", "pending")
    .eq("aggregator", trueLayer.id).maybeSingle();
  if (!conn) return new Response("Unknown or used link", { status: 400 });

  // The redirect fires whether or not the user approved, so ask the provider what actually happened.
  const { externalId, status } = await trueLayer.completeLink(conn.external_id, q, callbackUrl());
  if (status !== "linked") {
    if (status !== "pending") await admin().from("bank_connections").update({ status }).eq("id", conn.id);
    return Response.redirect("wince://bank-connected?status=failed", 302);
  }
  await admin().from("bank_connections").update({ status: "linked", external_id: externalId }).eq("id", conn.id);
  await syncUser(conn.user_id).catch(console.error);
  return Response.redirect("wince://bank-connected", 302);
}

async function syncUser(uid: string) {
  const { data: conns } = await admin().from("bank_connections").select().eq("user_id", uid).eq("status", "linked")
    .eq("aggregator", trueLayer.id);
  let accounts = 0;
  for (const conn of conns ?? []) {
    const s = await trueLayer.status(conn.external_id);
    if (s.status === "expired" || s.status === "rejected") {
      await admin().from("bank_connections").update({ status: "expired" }).eq("id", conn.id);
      continue;
    }
    for (const accId of s.accounts) {
      await syncAccount(uid, conn.provider, conn.external_id, accId);
      accounts++;
    }
  }
  return { accounts };
}

// Banks the app has its own colour and label for; everything else is "other" plus its name.
const KNOWN = ["revolut", "wise", "lloyds", "paypal"];
const providerKey = (bank: string) => KNOWN.find((k) => bank.toLowerCase().includes(k)) ?? "other";

async function syncAccount(uid: string, bank: string, consent: string, accId: string) {
  const { account, transactions } = await trueLayer.fetchAccount(consent, accId);
  const { data: source } = await admin().from("payment_sources").upsert({
    user_id: uid, provider: providerKey(bank), institution: bank, external_account_id: accId,
    account_name: account.name,
    current_balance: account.balance,
    currency: account.currency,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "user_id,external_account_id" }).select().single();

  const { data: existing } = await admin().from("financial_items").select("merchant_name").eq("user_id", uid);
  const known = new Set((existing ?? []).map((i) => norm(i.merchant_name)));

  await detectCardChecks(uid, source!.id, transactions.filter((t) => t.pending), known);
  const subs = recurring(transactions.filter((t) => !t.pending), known);
  if (subs.length) {
    const { error } = await admin().from("financial_items").insert(subs.map((i) => ({ ...i, user_id: uid, payment_source_id: source!.id })));
    if (error) throw error;
  }
}

/** £0.00 / £1.00 pending authorisations from an unknown merchant = probable free-trial card check. */
async function detectCardChecks(uid: string, sourceId: string, pending: Txn[], known: Set<string>) {
  const { data: prices } = await admin().from("merchant_prices").select();
  for (const t of pending) {
    const amt = t.amount;
    if (amt > 0 || amt < -1) continue;
    const name = t.merchant;
    if (known.has(norm(name))) continue;
    known.add(norm(name));

    const price = prices?.find((p) => norm(name).includes(p.merchant_key));
    const trialEnd = new Date(Date.now() + 7 * 864e5); // ponytail: assume 7-day trial until user confirms
    const { data: item, error } = await admin().from("financial_items").insert({
      user_id: uid, payment_source_id: sourceId, item_type: "free_trial", merchant_name: name,
      original_amount: 0, original_currency: price?.currency ?? t.currency,
      post_trial_amount: price?.amount ?? null, billing_cycle: price?.billing_cycle ?? "monthly",
      cancellation_url: price?.cancellation_url ?? null, trial_end_date: trialEnd.toISOString(),
      status: "pending_confirmation", auto_detected_via: "open_banking",
    }).select().single();
    if (error) throw error;

    const { data: profile } = await admin().from("profiles").select("fcm_token").eq("id", uid).single();
    if (profile?.fcm_token) {
      const est = price ? ` Likely ${money(price.amount, price.currency)}/${price.billing_cycle} after.` : "";
      await sendPush(profile.fcm_token, `New trial detected: ${name}?`,
        `We saw a card check from ${name}.${est} Tap to confirm the trial details.`,
        { type: "confirm_trial", item_id: item.id });
      await admin().from("alert_logs").insert({ financial_item_id: item.id, alert_stage: "confirm_trial" });
    }
  }
}
