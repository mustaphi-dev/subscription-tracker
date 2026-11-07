// Every 30 min via pg_cron: trial conversion alerts (7d / 3d / 24h) and account shortfalls.
import { admin, isServiceCall, json, money, sendPush } from "../_shared/mod.ts";

const STAGES = [
  { stage: "24_hours", hours: 24, label: "tomorrow" },
  { stage: "3_days", hours: 72, label: "in 3 days" },
  { stage: "7_days", hours: 168, label: "in 7 days" },
] as const;

// Same rule as the app's SourceLook.bank.
const LABELS: Record<string, string> = { revolut: "Revolut", wise: "Wise", lloyds: "Lloyds", paypal: "PayPal" };
type Source = { provider?: string | null; institution?: string | null; account_name?: string | null };
const bankLabel = (s: Source) => LABELS[s.provider ?? ""] ?? s.institution ?? s.account_name;

/** Claims an alert in alert_logs; null when it can't be claimed (23505: another run holds it). A failed push hands the claim back. */
async function claim(row: Record<string, string>) {
  const { data, error } = await admin().from("alert_logs").insert(row).select("id").single();
  if (error?.code !== "23505" && error) console.error("alert_logs claim", error);
  return error ? null : data.id as string;
}

async function deliver(id: string, token: string, title: string, body: string, data: Record<string, string>) {
  if (await sendPush(token, title, body, data)) return 1;
  const { error } = await admin().from("alert_logs").delete().eq("id", id);
  if (error) console.error("alert_logs release", error);
  return 0;
}

Deno.serve(async (req) => {
  if (!isServiceCall(req)) return json({ error: "forbidden" }, 403);
  let sent = 0;

  const { data: trials } = await admin().from("financial_items")
    .select("id, user_id, merchant_name, post_trial_amount, original_currency, gbp_equivalent_amount, trial_end_date, alert_logs(alert_stage), payment_sources(provider, institution, account_name), profiles:user_id(fcm_token, global_base_currency)")
    .eq("item_type", "free_trial").eq("status", "active")
    .gt("trial_end_date", new Date().toISOString())
    .lt("trial_end_date", new Date(Date.now() + STAGES[STAGES.length - 1].hours * 36e5).toISOString());

  for (const t of trials ?? []) {
    const token = (t as any).profiles?.fcm_token;
    if (!token) continue;
    const hoursLeft = (Date.parse(t.trial_end_date) - Date.now()) / 36e5;
    const done = new Set((t.alert_logs ?? []).map((a: any) => a.alert_stage));
    // Tightest window we're inside. Earlier stages are skipped if the trial was added late.
    const s = STAGES.find((s) => hoursLeft <= s.hours);
    if (!s || done.has(s.stage)) continue;
    const id = await claim({ financial_item_id: t.id, alert_stage: s.stage });
    if (!id) continue;

    const base = (t as any).profiles.global_base_currency;
    const charge = t.post_trial_amount != null ? money(t.post_trial_amount, t.original_currency) : "an unknown amount";
    const conv = t.original_currency !== base && t.gbp_equivalent_amount != null ? ` (≈ ${money(t.gbp_equivalent_amount, base)})` : "";
    const src = (t as any).payment_sources;
    const bank = src && bankLabel(src);
    sent += await deliver(id, token, `${t.merchant_name} trial ends ${s.label}`,
      `${charge}${conv} will be charged${bank ? ` to ${bank}` : ""} unless you cancel.`,
      { type: "trial", item_id: t.id });
  }

  const { data: shorts } = await admin().from("shortfall_check").select("*, profiles:user_id(fcm_token)");
  for (const s of shorts ?? []) {
    const token = (s as any).profiles?.fcm_token;
    if (!token) continue;
    const { count } = await admin().from("alert_logs").select("id", { count: "exact", head: true })
      .eq("payment_source_id", s.payment_source_id).eq("alert_stage", "shortfall")
      .gt("sent_at", new Date(Date.now() - 864e5).toISOString());
    if (count) continue;
    const id = await claim({ payment_source_id: s.payment_source_id, alert_stage: "shortfall" });
    if (!id) continue;
    const when = s.days_until_first === 0 ? "today" : s.days_until_first === 1 ? "tomorrow" : `in ${s.days_until_first} days`;
    sent += await deliver(id, token, `Top up ${bankLabel(s)} by ${money(s.shortfall, s.currency)}`,
      `${money(s.due_amount, s.currency)} is due ${when} and your balance is ${money(s.balance ?? 0, s.currency)}.`,
      { type: "shortfall", source_id: s.payment_source_id });
  }
  return json({ sent });
});
