// GoCardless Bank Account Data. Closed to new sign-ups, so it takes no new links;
// it stays so connections made with it keep syncing until they expire.
import { env } from "../../_shared/mod.ts";
import type { Aggregator, LinkStatus, Txn } from "./types.ts";

const GC = "https://bankaccountdata.gocardless.com/api/v2";
const INSTITUTIONS: Record<string, string> = {
  Lloyds: "LLOYDS_LOYDGB2L",
  Revolut: "REVOLUT_REVOGB21",
  Wise: "WISE_TRWIGB22",
  PayPal: "PAYPAL_PPLXLULL",
};

let token: { value: string; exp: number } | null = null;
async function gc(path: string, init: RequestInit = {}) {
  if (!token || token.exp < Date.now() + 60_000) {
    const r = await fetch(`${GC}/token/new/`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ secret_id: env("GOCARDLESS_SECRET_ID"), secret_key: env("GOCARDLESS_SECRET_KEY") }),
    }).then((r) => r.json());
    token = { value: r.access, exp: Date.now() + r.access_expires * 1000 };
  }
  const res = await fetch(`${GC}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${token.value}`, "content-type": "application/json", ...init.headers },
  });
  if (!res.ok) throw new Error(`gocardless ${path} ${res.status}: ${await res.text()}`);
  return res.json();
}

// Requisition codes: LN linked, RJ rejected, EX expired, SU suspended; everything else is mid-flow.
const STATUS: Record<string, LinkStatus> = { LN: "linked", RJ: "rejected", EX: "expired", SU: "expired" };

const txn = (t: any, pending: boolean): Txn => ({
  date: t.bookingDate ?? t.valueDate ?? new Date().toISOString().slice(0, 10),
  amount: Number(t.transactionAmount.amount),
  currency: t.transactionAmount.currency,
  merchant: t.creditorName ?? t.remittanceInformationUnstructured ?? "Unknown",
  pending,
});

export const gocardless: Aggregator = {
  id: "gocardless",
  countries: [],

  listBanks: async () => Object.keys(INSTITUTIONS).map((name) => ({ name })),

  async createLink({ bank, reference, redirect }) {
    const r = await gc("/requisitions/", {
      method: "POST",
      body: JSON.stringify({ institution_id: INSTITUTIONS[bank], reference, redirect, user_language: "EN" }),
    });
    return { externalId: r.id, link: r.link };
  },

  async completeLink(id) {
    return { externalId: id, status: (await this.status(id)).status };
  },

  async status(id) {
    const r = await gc(`/requisitions/${id}/`);
    return { status: STATUS[r.status] ?? "pending", accounts: r.accounts ?? [] };
  },

  // ponytail: GoCardless rate-limits to ~4 calls/account/endpoint/day; cron runs every 6h to fit.
  async fetchAccount(id) {
    const [{ account }, { balances }, { transactions }] = await Promise.all([
      gc(`/accounts/${id}/details/`),
      gc(`/accounts/${id}/balances/`),
      gc(`/accounts/${id}/transactions/`),
    ]);
    const bal = balances.find((b: any) => b.balanceType === "interimAvailable") ?? balances[0];
    return {
      account: {
        id,
        name: account.name ?? account.ownerName ?? bal.balanceAmount.currency,
        balance: Number(bal.balanceAmount.amount),
        currency: bal.balanceAmount.currency,
      },
      transactions: [
        ...(transactions.pending ?? []).map((t: any) => txn(t, true)),
        ...(transactions.booked ?? []).map((t: any) => txn(t, false)),
      ],
    };
  },
};
