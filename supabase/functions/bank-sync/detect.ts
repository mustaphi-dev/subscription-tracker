import type { Txn } from "./aggregators/types.ts";

export const norm = (s: string) => s.toLowerCase().replace(/[^a-z ]/g, "").replace(/\s+/g, " ").trim();

/** Same day next month, clamped to month end (Jan 31 -> Feb 28/29), like the app and SQL roll-forward. */
export function nextMonth(date: string) {
  const [y, m, d] = date.slice(0, 10).split("-").map(Number);
  const last = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return new Date(Date.UTC(y, m, Math.min(d, last))).toISOString().slice(0, 10);
}

/** ≥2 debits to the same merchant, similar amount, ~monthly apart = subscription. */
export function recurring(booked: Txn[], known: Set<string>) {
  const groups = new Map<string, Txn[]>();
  for (const t of booked) {
    if (t.amount >= 0) continue;
    const k = norm(t.merchant);
    if (!known.has(k)) groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  const found = [];
  for (const txs of groups.values()) {
    if (txs.length < 2) continue;
    txs.sort((a, b) => a.date.localeCompare(b.date));
    const [prev, last] = txs.slice(-2);
    const gapDays = (Date.parse(last.date) - Date.parse(prev.date)) / 864e5;
    const sameAmount = Math.abs(last.amount - prev.amount) <= Math.abs(prev.amount) * 0.1;
    if (gapDays < 25 || gapDays > 35 || !sameAmount) continue;
    found.push({
      item_type: "subscription", merchant_name: last.merchant, original_amount: Math.abs(last.amount),
      original_currency: last.currency, billing_cycle: "monthly",
      next_renewal_date: nextMonth(last.date), auto_detected_via: "open_banking",
      total_spent: txs.reduce((s, t) => s + Math.abs(t.amount), 0),
    });
  }
  return found;
}
