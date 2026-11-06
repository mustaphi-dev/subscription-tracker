// Self-check: feeds a raw email through the worker with a stubbed fetch.
import assert from "node:assert";
import worker from "./index.js";

const raw = "From: Me <me@gmail.com>\r\nTo: trials+abc@trywince.app\r\nSubject: Fwd: Your Netflix trial\r\nDate: Fri, 6 Nov 2026 10:00:00 +0000\r\nContent-Type: text/plain\r\n\r\nYour free trial ends 20 Nov. Then £10.99/month.\r\n";
let sent, rejected;
globalThis.fetch = async (url, init) => { sent = { url, body: JSON.parse(init.body) }; return { ok: globalThis.ok }; };
const msg = { to: "trials+abc@trywince.app", from: "me@gmail.com", raw: new Blob([raw]).stream(), setReject: (r) => (rejected = r) };

globalThis.ok = true;
await worker.email(msg, { FUNCTION_URL: "https://x/fn", INBOUND_SECRET: "s&1" });
assert.equal(sent.url, "https://x/fn?secret=s%261");
assert.equal(sent.body.OriginalRecipient, "trials+abc@trywince.app");
assert.match(sent.body.TextBody, /£10.99/);
assert.equal(rejected, undefined);

globalThis.ok = false;
await worker.email({ ...msg, raw: new Blob([raw]).stream() }, { FUNCTION_URL: "https://x/fn", INBOUND_SECRET: "s" });
assert.ok(rejected);
console.log("worker ok");
