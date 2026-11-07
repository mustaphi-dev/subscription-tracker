// deno test --allow-env supabase/functions/bank-sync/
import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.13";

Deno.env.set("TRUELAYER_CLIENT_ID", "cid");
Deno.env.set("TRUELAYER_CLIENT_SECRET", "secret");
Deno.env.set("BANK_TOKEN_KEY", btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))));

const { trueLayer, useTokenStore } = await import("./truelayer.ts");
const { seal, open } = await import("../tokens.ts");
type Tokens = { access: string; refresh: string | null; expiresAt: number };

const mem = new Map<string, Tokens>();
useTokenStore({
  get: async (id) => mem.get(id) ?? null,
  put: async (id, t) => void mem.set(id, t),
  remove: async (id) => void mem.delete(id),
});

type Route = (url: URL, init?: RequestInit) => { status?: number; body: unknown };
function stub(routes: Record<string, Route>) {
  const calls: { url: URL; init?: RequestInit }[] = [];
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    calls.push({ url, init });
    const r = routes[`${init?.method ?? "GET"} ${url.host}${url.pathname}`];
    if (!r) return Promise.resolve(new Response(`no route ${url}`, { status: 404 }));
    const { status = 200, body } = r(url, init);
    return Promise.resolve(Response.json(body, { status }));
  };
  return calls;
}
const form = (init?: RequestInit) => new URLSearchParams(String(init?.body));

Deno.test("tokens round-trip through AES-GCM and differ each time", async () => {
  const t = { access: "a", refresh: "r", expiresAt: 1 };
  const a = await seal(t), b = await seal(t);
  assertEquals(a === b, false);
  assertEquals(await open(a), t);
});

Deno.test("sandbox: auth link goes to the sandbox, keyed by our reference", async () => {
  Deno.env.set("TRUELAYER_ENV", "sandbox");
  try {
    const { externalId, link } = await trueLayer.createLink({ bank: "Mock Bank", country: "GB", reference: "ref-1", redirect: "https://x/cb" });
    const u = new URL(link);
    assertEquals(externalId, "ref-1");
    assertEquals(u.host, "auth.truelayer-sandbox.com");
    assertEquals(u.searchParams.get("state"), "ref-1");
  } finally {
    Deno.env.delete("TRUELAYER_ENV");
  }
});

Deno.test("production bank list comes from /api/providers, filtered to the country", async () => {
  const calls = stub({
    "GET auth.truelayer.com/api/providers": () => ({
      body: [
        { provider_id: "ob-monzo", display_name: "Monzo", logo_url: "m.svg", country: "uk" },
        { provider_id: "ob-aib", display_name: "AIB", country: "ie" },
        { provider_id: "ob-barclays", display_name: "Barclays", country: "uk" },
      ],
    }),
  });
  // TrueLayer uses "uk"; our country code is GB.
  const banks = await trueLayer.listBanks("GB");
  assertEquals(calls[0].url.searchParams.get("clientId"), "cid");
  assertEquals(banks.map((b) => b.name), ["Barclays", "Monzo"]);
});

Deno.test("cancelled consent is rejected; approved code is exchanged and stored", async () => {
  assertEquals((await trueLayer.completeLink("r0", new URLSearchParams({ error: "access_denied" }), "https://x/cb")).status, "rejected");
  const calls = stub({
    "POST auth.truelayer.com/connect/token": () => ({ body: { access_token: "AT", refresh_token: "RT", expires_in: 3600 } }),
  });
  const r = await trueLayer.completeLink("r1", new URLSearchParams({ code: "c0de", state: "r1" }), "https://x/cb");
  assertEquals(r, { externalId: "r1", status: "linked" });
  const f = form(calls[0].init);
  assertEquals([f.get("grant_type"), f.get("code"), f.get("client_secret")], ["authorization_code", "c0de", "secret"]);
  assertEquals(f.get("redirect_uri"), "https://x/cb");
  assertEquals(mem.get("r1")?.refresh, "RT");
});

Deno.test("expired access token is refreshed before data calls", async () => {
  mem.set("r2", { access: "old", refresh: "RT", expiresAt: Date.now() - 1 });
  const calls = stub({
    "POST auth.truelayer.com/connect/token": () => ({ body: { access_token: "NEW", expires_in: 3600 } }),
    "GET api.truelayer.com/data/v1/accounts": () => ({ body: { results: [{ account_id: "a1" }, { account_id: "a2" }] } }),
  });
  assertEquals(await trueLayer.status("r2"), { status: "linked", accounts: ["a1", "a2"] });
  assertEquals(form(calls[0].init).get("grant_type"), "refresh_token");
  assertEquals((calls[1].init?.headers as Record<string, string>).authorization, "Bearer NEW");
  // Refresh token kept when TrueLayer doesn't send a new one.
  assertEquals(mem.get("r2")?.refresh, "RT");
});

Deno.test("revoked refresh token marks the link expired and forgets the tokens", async () => {
  mem.set("r3", { access: "old", refresh: "RT", expiresAt: Date.now() - 1 });
  stub({ "POST auth.truelayer.com/connect/token": () => ({ status: 400, body: { error: "invalid_grant" } }) });
  assertEquals(await trueLayer.status("r3"), { status: "expired", accounts: [] });
  assertEquals(mem.has("r3"), false);
});

Deno.test("account fetch: available balance, debit signs, pending flagged, merchant fallback", async () => {
  mem.set("r4", { access: "AT", refresh: "RT", expiresAt: Date.now() + 3600_000 });
  stub({
    "GET api.truelayer.com/data/v1/accounts": () => ({ body: { results: [{ account_id: "a1", display_name: "Current Account", currency: "GBP" }] } }),
    "GET api.truelayer.com/data/v1/accounts/a1/balance": () => ({ body: { results: [{ currency: "GBP", available: 82.5, current: 100 }] } }),
    "GET api.truelayer.com/data/v1/accounts/a1/transactions": (u) => ({
      body: {
        results: u.searchParams.get("from") ? [
          { timestamp: "2026-10-01T00:00:00+00:00", description: "NETFLIX.COM", amount: -10.99, currency: "GBP", transaction_type: "DEBIT", merchant_name: "Netflix" },
          { timestamp: "2026-10-28T00:00:00+00:00", description: "SALARY ACME", amount: 1500, currency: "GBP", transaction_type: "CREDIT" },
        ] : [],
      },
    }),
    "GET api.truelayer.com/data/v1/accounts/a1/transactions/pending": () => ({ status: 501, body: { error: "endpoint_not_supported" } }),
  });
  const { account, transactions } = await trueLayer.fetchAccount("r4", "a1");
  assertEquals(account, { id: "a1", name: "Current Account", balance: 82.5, currency: "GBP" });
  assertEquals(transactions.map((t) => [t.merchant, t.amount, t.pending, t.date]), [
    ["Netflix", -10.99, false, "2026-10-01"],
    ["SALARY ACME", 1500, false, "2026-10-28"],
  ]);
});

Deno.test("pending fetch: unsupported is none, other failures surface", async () => {
  mem.set("r5", { access: "AT", refresh: "RT", expiresAt: Date.now() + 3600_000 });
  stub({
    "GET api.truelayer.com/data/v1/accounts": () => ({ body: { results: [{ account_id: "a1" }] } }),
    "GET api.truelayer.com/data/v1/accounts/a1/balance": () => ({ body: { results: [] } }),
    "GET api.truelayer.com/data/v1/accounts/a1/transactions": () => ({ body: { results: [] } }),
    "GET api.truelayer.com/data/v1/accounts/a1/transactions/pending": () => ({ status: 500, body: {} }),
  });
  await assertRejects(() => trueLayer.fetchAccount("r5", "a1"));
});
