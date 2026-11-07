// AI receipt / email trial extraction.
// 1) App upload:   POST, user JWT, { image_base64, media_type } or { text }
// 2) Postmark inbound webhook: POST ?secret=<INBOUND_WEBHOOK_SECRET>, Postmark JSON body.
import { admin, env, json, userFrom } from "../_shared/mod.ts";

const SCHEMA = {
  type: "object",
  properties: {
    is_relevant: { type: "boolean", description: "false if this is not a subscription/trial/installment receipt" },
    item_type: { type: "string", enum: ["free_trial", "subscription", "installment"] },
    merchant_name: { type: "string" },
    trial_start_date: { type: ["string", "null"], description: "ISO 8601" },
    trial_end_date: { type: ["string", "null"], description: "ISO 8601 date-time when the first paid charge happens" },
    amount: { type: "number", description: "amount charged now (0 for a free trial)" },
    post_trial_amount: { type: ["number", "null"], description: "recurring amount charged after the trial ends" },
    currency: { type: "string", description: "ISO 4217, e.g. GBP, USD, EUR, GHS" },
    billing_cycle: { type: "string", enum: ["weekly", "monthly", "quarterly", "yearly", "once"] },
    next_charge_date: { type: ["string", "null"], description: "ISO date of next charge for subscriptions/installments" },
    payment_source: { type: ["string", "null"], enum: ["revolut", "wise", "lloyds", "paypal", null] },
    cancellation_url: { type: ["string", "null"] },
    installment_total_count: { type: ["integer", "null"] },
    installment_paid_count: { type: ["integer", "null"] },
    installment_remaining_balance: { type: ["number", "null"] },
  },
  required: ["is_relevant", "item_type", "merchant_name", "amount", "currency", "billing_cycle"],
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const url = new URL(req.url);
  let uid: string | null;
  let content: unknown[];

  if (url.searchParams.has("secret")) {
    if (url.searchParams.get("secret") !== env("INBOUND_WEBHOOK_SECRET")) return json({ error: "forbidden" }, 403);
    const mail = await req.json();
    const to = [mail.OriginalRecipient, ...(mail.ToFull ?? []).map((t: any) => t.Email)].filter(Boolean);
    const { data } = await admin().from("profiles").select("id").in("inbound_parse_email", to.map((t) => t.toLowerCase())).maybeSingle();
    uid = data?.id ?? null;
    if (!uid) return json({ ignored: "unknown recipient" }); // 200 so Postmark doesn't retry
    content = [{ type: "text", text: `Subject: ${mail.Subject}\nFrom: ${mail.From}\nDate: ${mail.Date}\n\n${mail.TextBody || mail.HtmlBody}`.slice(0, 60_000) }];
  } else {
    uid = await userFrom(req);
    if (!uid) return json({ error: "unauthorised" }, 401);
    const body = await req.json();
    content = body.image_base64
      ? [{ type: "image", source: { type: "base64", media_type: body.media_type ?? "image/png", data: body.image_base64 } }]
      : [{ type: "text", text: String(body.text ?? "").slice(0, 60_000) }];
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": env("ANTHROPIC_API_KEY"), "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-5-5",
      max_tokens: 1024,
      tools: [{ name: "record_item", description: "Record the extracted billing item", input_schema: SCHEMA }],
      tool_choice: { type: "tool", name: "record_item" },
      messages: [{
        role: "user",
        content: [...content, {
          type: "text",
          text: `Today is ${new Date().toISOString().slice(0, 10)}. Extract the subscription, free trial or installment plan ` +
            `(e.g. PayPal Pay in 3) from this receipt. If the trial length is given but not the end date, compute it. ` +
            `Use null for anything not stated.`,
        }],
      }],
    }),
  });
  if (!res.ok) {
    console.error("ai", res.status, await res.text());
    return json({ error: `ai ${res.status}` }, 502);
  }
  const x = (await res.json()).content.find((c: any) => c.type === "tool_use")?.input;
  if (!x?.is_relevant) return json({ ignored: "not a billing receipt" });

  // A second receipt for something already tracked (monthly invoice, re-forwarded email) isn't a new item.
  // ponytail: exact merchant name match; "Canva" vs "Canva Pro" still slips through, normalise names if that bites.
  const { data: dup } = await admin().from("financial_items").select("id, merchant_name")
    .eq("user_id", uid).eq("item_type", x.item_type).neq("status", "cancelled")
    .ilike("merchant_name", x.merchant_name.replace(/[%_\\]/g, "\\$&"))
    .limit(1).maybeSingle();
  if (dup) return json({ duplicate: dup });

  const { data: source } = x.payment_source
    ? await admin().from("payment_sources").select("id").eq("user_id", uid).eq("provider", x.payment_source).limit(1).maybeSingle()
    : { data: null };

  const { data: item, error } = await admin().from("financial_items").insert({
    user_id: uid,
    payment_source_id: source?.id ?? null,
    item_type: x.item_type,
    merchant_name: x.merchant_name,
    original_amount: x.item_type === "free_trial" ? 0 : x.amount,
    original_currency: x.currency.toUpperCase(),
    post_trial_amount: x.post_trial_amount,
    trial_end_date: x.trial_end_date,
    next_renewal_date: x.item_type === "free_trial" ? x.trial_end_date?.slice(0, 10) : x.next_charge_date,
    billing_cycle: x.billing_cycle,
    cancellation_url: x.cancellation_url,
    installment_total_count: x.installment_total_count,
    installment_paid_count: x.installment_paid_count ?? 0,
    installment_remaining_balance: x.installment_remaining_balance,
    auto_detected_via: "email_ai",
  }).select().single();
  if (error) return json({ error: error.message }, 500);
  return json({ item });
});
