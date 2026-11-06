// Enable Banking (https://enablebanking.com/docs/api/reference/). UK and EU banks.
// Secrets: ENABLE_BANKING_APP_ID (the application id, used as the JWT kid) and
// ENABLE_BANKING_PRIVATE_KEY (the application's RSA private key, PEM).
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { env } from "../../_shared/mod.ts";
import type { Aggregator, Bank, LinkStatus, Txn } from "./types.ts";

const API = "https://api.enablebanking.com";
const MAX_CONSENT_DAYS = 90;
const HISTORY_DAYS = 90;

let token: { value: string; exp: number } | null = null;
async function jwt() {
  if (token && token.exp > Date.now() + 60_000) return token.value;
  // Keys exported as PKCS#1 ("BEGIN RSA PRIVATE KEY") need converting to PKCS#8 first; see README.
  const key = await importPKCS8(env("ENABLE_BANKING_PRIVATE_KEY"), "RS256");
  const now = Math.floor(Date.now() / 1000);
  const ttl = 3600; // the API rejects tokens living longer than 24h
  const value = await new SignJWT({})
    .setProtectedHeader({ typ: "JWT", alg: "RS256", kid: env("ENABLE_BANKING_APP_ID") })
    .setIssuer("enablebanking.com").setAudience("api.enablebanking.com")
    .setIssuedAt(now).setExpirationTime(now + ttl)
    .sign(key);
  token = { value, exp: (now + ttl) * 1000 };
  return value;
}

async function eb(path: string, init: RequestInit = {}) {
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${await jwt()}`, "content-type": "application/json", ...init.headers },
  });
  if (!res.ok) throw new Error(`enablebanking ${init.method ?? "GET"} ${path.split("?")[0]} ${res.status}: ${await res.text()}`);
  return res.json();
}

// Bank lists change rarely; keep each country's for an hour per function instance.
const banks = new Map<string, { at: number; list: any[] }>();
async function aspsps(country: string) {
  const hit = banks.get(country);
  if (hit && hit.at > Date.now() - 3600_000) return hit.list;
  const { aspsps } = await eb(`/aspsps?country=${country}&psu_type=personal&service=AIS`);
  banks.set(country, { at: Date.now(), list: aspsps });
  return aspsps as any[];
}

// Session statuses. Only AUTHORIZED is shown in the docs' examples; the rest follow the API's enum
// as far as we know it, and anything unrecognised is treated as still in progress.
const STATUS: Record<string, LinkStatus> = {
  AUTHORIZED: "linked",
  EXPIRED: "expired", REVOKED: "expired", CLOSED: "expired",
  CANCELLED: "rejected", INVALID: "rejected",
};

// Best available balance first: interim available, closing available, then booked.
const BALANCE_ORDER = ["ITAV", "CLAV", "XPCD", "ITBD", "CLBD"];

const txn = (t: any): Txn => {
  const debit = t.credit_debit_indicator === "DBIT";
  const party = debit ? t.creditor?.name : t.debtor?.name;
  return {
    date: t.booking_date ?? t.value_date ?? t.transaction_date ?? new Date().toISOString().slice(0, 10),
    amount: Math.abs(Number(t.transaction_amount.amount)) * (debit ? -1 : 1),
    currency: t.transaction_amount.currency,
    merchant: party || (t.remittance_information ?? []).join(" ").trim() || "Unknown",
    pending: t.status === "PDNG",
  };
};

export const enableBanking: Aggregator = {
  id: "enablebanking",
  countries: ["GB"],

  async listBanks(country) {
    return (await aspsps(country))
      .filter((a) => !a.beta)
      .map((a): Bank => ({ name: a.name, logo: a.logo }));
  },

  async createLink({ bank, country, reference, redirect }) {
    const aspsp = (await aspsps(country)).find((a) => a.name === bank);
    if (!aspsp) throw new Error(`enablebanking: unknown bank ${bank} in ${country}`);
    const maxDays = aspsp.maximum_consent_validity ? Math.floor(aspsp.maximum_consent_validity / 86400) : MAX_CONSENT_DAYS;
    const validUntil = new Date(Date.now() + Math.min(maxDays, MAX_CONSENT_DAYS) * 864e5);
    const r = await eb("/auth", {
      method: "POST",
      body: JSON.stringify({
        access: { valid_until: validUntil.toISOString() },
        aspsp: { name: aspsp.name, country: aspsp.country },
        state: reference,
        redirect_url: redirect,
        psu_type: "personal",
      }),
    });
    return { externalId: r.authorization_id, link: r.url };
  },

  async completeLink(externalId, query) {
    // The bank sends ?error=access_denied when the user cancels or declines.
    const code = query.get("code");
    if (query.get("error") || !code) return { externalId, status: "rejected" };
    const s = await eb("/sessions", { method: "POST", body: JSON.stringify({ code }) });
    return { externalId: s.session_id, status: "linked" };
  },

  async status(sessionId) {
    const s = await eb(`/sessions/${sessionId}`);
    const expired = s.access?.valid_until && Date.parse(s.access.valid_until) < Date.now();
    const accounts = (s.accounts ?? []).map((a: any) => (typeof a === "string" ? a : a.uid));
    return { status: expired ? "expired" : STATUS[s.status] ?? "pending", accounts };
  },

  async fetchAccount(uid) {
    const from = new Date(Date.now() - HISTORY_DAYS * 864e5).toISOString().slice(0, 10);
    const [details, { balances }] = await Promise.all([eb(`/accounts/${uid}/details`), eb(`/accounts/${uid}/balances`)]);

    const transactions: Txn[] = [];
    let key: string | undefined;
    for (let page = 0; page < 20; page++) {
      const q = new URLSearchParams({ date_from: from });
      if (key) q.set("continuation_key", key);
      const r = await eb(`/accounts/${uid}/transactions?${q}`);
      transactions.push(...(r.transactions ?? []).map(txn));
      key = r.continuation_key;
      if (!key) break;
    }

    const bal = BALANCE_ORDER.map((t) => balances.find((b: any) => b.balance_type === t)).find(Boolean) ?? balances[0];
    return {
      account: {
        id: uid,
        name: details.name ?? details.product ?? bal?.name ?? details.currency,
        balance: Number(bal?.balance_amount.amount ?? 0),
        currency: bal?.balance_amount.currency ?? details.currency,
      },
      transactions,
    };
  },
};
