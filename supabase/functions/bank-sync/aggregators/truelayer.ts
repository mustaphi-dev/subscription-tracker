// TrueLayer Data API v1 (https://docs.truelayer.com/docs/data-api-basics). UK banks.
// Secrets: TRUELAYER_CLIENT_ID, TRUELAYER_CLIENT_SECRET, BANK_TOKEN_KEY, and
// TRUELAYER_ENV=sandbox to use TrueLayer's sandbox and its Mock bank (login john / doe).
import { env } from "../../_shared/mod.ts";
import { dbTokens, type TokenStore, type Tokens } from "../tokens.ts";
import type { Aggregator, Bank, LinkStatus, Txn } from "./types.ts";

const sandbox = () => Deno.env.get("TRUELAYER_ENV") === "sandbox";
const AUTH = () => (sandbox() ? "https://auth.truelayer-sandbox.com" : "https://auth.truelayer.com");
const API = () => (sandbox() ? "https://api.truelayer-sandbox.com" : "https://api.truelayer.com");
const SCOPES = "info accounts balance transactions offline_access";
const HISTORY_DAYS = 90;

let store: TokenStore = dbTokens;
/** Tests swap in an in-memory store. */
export const useTokenStore = (s: TokenStore) => (store = s);

class Expired extends Error {}
class NotSupported extends Error {}

async function tokenRequest(form: Record<string, string>): Promise<Tokens> {
  const res = await fetch(`${AUTH()}/connect/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env("TRUELAYER_CLIENT_ID"), client_secret: env("TRUELAYER_CLIENT_SECRET"), ...form }),
  });
  const body = await res.json().catch(() => ({}));
  // invalid_grant = the code or refresh token is used, expired or revoked: the user must reconnect.
  if (body.error === "invalid_grant") throw new Expired(body.error_description ?? "invalid_grant");
  if (!res.ok) throw new Error(`truelayer token ${res.status}: ${JSON.stringify(body)}`);
  return { access: body.access_token, refresh: body.refresh_token ?? null, expiresAt: Date.now() + body.expires_in * 1000 };
}

async function accessToken(id: string): Promise<string> {
  const t = await store.get(id);
  if (!t) throw new Expired("no tokens stored");
  if (t.expiresAt > Date.now() + 60_000) return t.access;
  if (!t.refresh) throw new Expired("access token expired and no refresh token");
  const fresh = await tokenRequest({ grant_type: "refresh_token", refresh_token: t.refresh });
  await store.put(id, { ...fresh, refresh: fresh.refresh ?? t.refresh });
  return fresh.access;
}

async function data(id: string, path: string) {
  const res = await fetch(`${API()}/data/v1${path}`, { headers: { authorization: `Bearer ${await accessToken(id)}` } });
  if (res.status === 401) throw new Expired(`data ${path} 401`);
  if (res.status === 501) throw new NotSupported(`data ${path} 501`);
  if (!res.ok) throw new Error(`truelayer ${path.split("?")[0]} ${res.status}: ${await res.text()}`);
  return (await res.json()).results ?? [];
}

// status() and each fetchAccount() all need the account list; share one call per sync
// so the 4-a-day unattended limit isn't spent on repeats.
const accountsMemo = new Map<string, { at: number; list: Promise<any[]> }>();
function accountList(id: string) {
  const hit = accountsMemo.get(id);
  if (hit && hit.at > Date.now() - 300_000) return hit.list;
  const list = data(id, "/accounts");
  list.catch(() => accountsMemo.delete(id));
  accountsMemo.set(id, { at: Date.now(), list });
  return list;
}

const providers = new Map<string, { at: number; list: { id: string; name: string; logo?: string }[] }>();
async function providerList(country: string) {
  if (sandbox()) return [{ id: "mock", name: "Mock Bank" }];
  const hit = providers.get(country);
  if (hit && hit.at > Date.now() - 3600_000) return hit.list;
  // TrueLayer labels the UK "uk" rather than ISO "gb"; accept either.
  const codes = country === "GB" ? ["uk", "gb"] : [country.toLowerCase()];
  const q = new URLSearchParams({ clientId: env("TRUELAYER_CLIENT_ID"), country: codes[0], scopes: SCOPES.replace(" offline_access", "") });
  const res = await fetch(`${AUTH()}/api/providers?${q}`);
  if (!res.ok) throw new Error(`truelayer providers ${res.status}: ${await res.text()}`);
  const list = ((await res.json()) as any[])
    .filter((p) => !p.country || codes.includes(String(p.country).toLowerCase()))
    .map((p) => ({ id: p.provider_id, name: p.display_name, logo: p.logo_url }))
    .sort((a, b) => a.name.localeCompare(b.name));
  providers.set(country, { at: Date.now(), list });
  return list;
}

const txn = (t: any, pending: boolean): Txn => {
  const raw = Number(t.amount);
  // TrueLayer marks direction in transaction_type; don't trust the amount's sign alone.
  const amount = t.transaction_type === "DEBIT" ? -Math.abs(raw) : t.transaction_type === "CREDIT" ? Math.abs(raw) : raw;
  return {
    date: String(t.timestamp ?? "").slice(0, 10) || new Date().toISOString().slice(0, 10),
    amount,
    currency: t.currency,
    merchant: t.merchant_name || t.description || "Unknown",
    pending,
  };
};

export const trueLayer: Aggregator = {
  id: "truelayer",
  countries: ["GB"],

  async listBanks(country) {
    return (await providerList(country)).map((p): Bank => ({ name: p.name, logo: p.logo }));
  },

  async createLink({ bank, country, reference, redirect }) {
    const p = (await providerList(country)).find((x) => x.name === bank);
    if (!p) throw new Error(`truelayer: unknown bank ${bank}`);
    const q = new URLSearchParams({
      response_type: "code",
      client_id: env("TRUELAYER_CLIENT_ID"),
      scope: SCOPES,
      redirect_uri: redirect,
      providers: sandbox() ? "uk-cs-mock" : "uk-ob-all uk-oauth-all",
      provider_id: p.id,
      state: reference,
    });
    // TrueLayer has no id until the code comes back, so the consent is keyed by our reference.
    return { externalId: reference, link: `${AUTH()}/?${q}` };
  },

  async completeLink(externalId, query, redirect) {
    const code = query.get("code");
    if (query.get("error") || !code) return { externalId, status: "rejected" };
    try {
      const t = await tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirect });
      await store.put(externalId, t);
      return { externalId, status: "linked" };
    } catch (e) {
      if (e instanceof Expired) return { externalId, status: "rejected" };
      throw e;
    }
  },

  async status(externalId) {
    try {
      const accounts = await accountList(externalId);
      return { status: "linked" as LinkStatus, accounts: accounts.map((a: any) => a.account_id) };
    } catch (e) {
      if (e instanceof Expired) {
        await store.remove(externalId);
        return { status: "expired" as LinkStatus, accounts: [] };
      }
      throw e;
    }
  },

  // Background refreshes are limited to 4 calls a day per endpoint; cron runs every 6h to fit.
  async fetchAccount(consent, id) {
    const from = new Date(Date.now() - HISTORY_DAYS * 864e5).toISOString().slice(0, 10);
    const to = new Date().toISOString().slice(0, 10);
    const [accounts, balances, booked, pending] = await Promise.all([
      accountList(consent),
      data(consent, `/accounts/${id}/balance`),
      data(consent, `/accounts/${id}/transactions?from=${from}&to=${to}`),
      // Some banks don't support pending transactions; treat that as none.
      data(consent, `/accounts/${id}/transactions/pending`).catch((e) => {
        if (e instanceof NotSupported) return [];
        throw e;
      }),
    ]);
    const acc = accounts.find((a: any) => a.account_id === id) ?? {};
    const bal = balances[0] ?? {};
    return {
      account: {
        id,
        name: acc.display_name ?? acc.account_type ?? "Account",
        balance: Number(bal.available ?? bal.current ?? 0),
        currency: bal.currency ?? acc.currency ?? "GBP",
      },
      transactions: [...pending.map((t: any) => txn(t, true)), ...booked.map((t: any) => txn(t, false))],
    };
  },
};
