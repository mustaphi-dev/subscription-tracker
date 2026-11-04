import { admin, isServiceCall, json } from "../_shared/mod.ts";

// Every 6h via pg_cron. open.er-api.com is keyless and covers GHS.
Deno.serve(async (req) => {
  if (!isServiceCall(req)) return json({ error: "forbidden" }, 403);
  const res = await fetch("https://open.er-api.com/v6/latest/USD");
  const body = await res.json();
  if (body.result !== "success") return json({ error: "fx provider failed" }, 502);

  const now = new Date().toISOString();
  const rows = Object.entries(body.rates as Record<string, number>).map(([target_currency, rate]) => ({
    base_currency: "USD", target_currency, rate, updated_at: now,
  }));
  const { error } = await admin.from("fx_rates").upsert(rows);
  if (error) return json({ error: error.message }, 500);
  await admin.rpc("refresh_base_amounts");
  return json({ updated: rows.length });
});
