// deno test --allow-env supabase/functions/bank-sync/aggregators/enablebanking_test.ts
import { assertEquals } from "jsr:@std/assert@1.0.13";

const { privateKey } = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true, ["sign", "verify"],
);
const der = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8", privateKey))));
Deno.env.set("ENABLE_BANKING_PRIVATE_KEY", `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`);
Deno.env.set("ENABLE_BANKING_APP_ID", "app-123");
Deno.env.set("SUPABASE_URL", "http://localhost");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test");

const { enableBanking } = await import("./enablebanking.ts");

/** Swap fetch for a router of canned API responses; records every request. */
function stub(routes: Record<string, (url: URL, init?: RequestInit) => unknown>) {
  const calls: { url: URL; init?: RequestInit }[] = [];
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    calls.push({ url, init });
    const key = `${init?.method ?? "GET"} ${url.pathname}`;
    const route = routes[key];
    if (!route) return Promise.resolve(new Response(`no route ${key}`, { status: 404 }));
    return Promise.resolve(Response.json(route(url, init)));
  };
  return calls;
}

Deno.test("cancelled consent is rejected without calling the API", async () => {
  const calls = stub({});
  const r = await enableBanking.completeLink("auth-1", new URLSearchParams({ error: "access_denied", state: "x" }));
  assertEquals(r, { externalId: "auth-1", status: "rejected" });
  assertEquals(calls.length, 0);
});

Deno.test("approved consent swaps the authorization id for the session id", async () => {
  const calls = stub({ "POST /sessions": () => ({ session_id: "sess-9", accounts: [{ uid: "acc-1" }] }) });
  const r = await enableBanking.completeLink("auth-1", new URLSearchParams({ code: "c0de", state: "x" }));
  assertEquals(r, { externalId: "sess-9", status: "linked" });
  assertEquals(JSON.parse(String(calls[0].init?.body)), { code: "c0de" });
  // Signed JWT carries the app id as kid.
  const jwt = String((calls[0].init?.headers as Record<string, string>).authorization).split(" ")[1];
  assertEquals(JSON.parse(atob(jwt.split(".")[0])).kid, "app-123");
});

Deno.test("session status maps to link status", async () => {
  const future = new Date(Date.now() + 864e5).toISOString();
  stub({ "GET /sessions/s1": () => ({ status: "AUTHORIZED", accounts: ["a", "b"], access: { valid_until: future } }) });
  assertEquals(await enableBanking.status("s1"), { status: "linked", accounts: ["a", "b"] });
  stub({ "GET /sessions/s1": () => ({ status: "AUTHORIZED", accounts: [], access: { valid_until: "2020-01-01T00:00:00Z" } }) });
  assertEquals((await enableBanking.status("s1")).status, "expired");
  stub({ "GET /sessions/s1": () => ({ status: "REVOKED", accounts: [] }) });
  assertEquals((await enableBanking.status("s1")).status, "expired");
});

Deno.test("account fetch picks the available balance, signs debits and follows pages", async () => {
  stub({
    "GET /accounts/u1/details": () => ({ uid: "u1", name: "Club Lloyds", currency: "GBP" }),
    "GET /accounts/u1/balances": () => ({
      balances: [
        { balance_type: "CLBD", balance_amount: { amount: "100.00", currency: "GBP" } },
        { balance_type: "ITAV", balance_amount: { amount: "82.50", currency: "GBP" } },
      ],
    }),
    "GET /accounts/u1/transactions": (url) => url.searchParams.get("continuation_key")
      ? { transactions: [{ transaction_amount: { amount: "1500.00", currency: "GBP" }, credit_debit_indicator: "CRDT", status: "BOOK", booking_date: "2026-10-28", debtor: { name: "ACME LTD" } }] }
      : {
        continuation_key: "next",
        transactions: [
          { transaction_amount: { amount: "10.99", currency: "GBP" }, credit_debit_indicator: "DBIT", status: "BOOK", booking_date: "2026-10-01", creditor: { name: "NETFLIX.COM" } },
          { transaction_amount: { amount: "0.00", currency: "GBP" }, credit_debit_indicator: "DBIT", status: "PDNG", value_date: "2026-11-05", remittance_information: ["SPOTIFY P1234"] },
        ],
      },
  });
  const { account, transactions } = await enableBanking.fetchAccount("sess", "u1");
  assertEquals(account, { id: "u1", name: "Club Lloyds", balance: 82.5, currency: "GBP" });
  assertEquals(transactions.map((t) => [t.merchant, t.amount, t.pending, t.date]), [
    ["NETFLIX.COM", -10.99, false, "2026-10-01"],
    ["SPOTIFY P1234", -0, true, "2026-11-05"],
    ["ACME LTD", 1500, false, "2026-10-28"],
  ]);
});

Deno.test("auth request caps consent at the bank's maximum", async () => {
  const calls = stub({
    "GET /aspsps": () => ({ aspsps: [{ name: "Monzo", country: "GB", maximum_consent_validity: 30 * 86400 }] }),
    "POST /auth": () => ({ url: "https://bank.example/consent", authorization_id: "auth-7" }),
  });
  const r = await enableBanking.createLink({ bank: "Monzo", country: "GB", reference: "ref-1", redirect: "https://x/cb" });
  assertEquals(r, { externalId: "auth-7", link: "https://bank.example/consent" });
  const body = JSON.parse(String(calls.find((c) => c.url.pathname === "/auth")!.init?.body));
  assertEquals(body.aspsp, { name: "Monzo", country: "GB" });
  assertEquals(body.state, "ref-1");
  const days = (Date.parse(body.access.valid_until) - Date.now()) / 864e5;
  assertEquals(Math.round(days), 30);
});
