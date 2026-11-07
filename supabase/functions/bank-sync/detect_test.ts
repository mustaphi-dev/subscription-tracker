import { assertEquals } from "jsr:@std/assert@1.0.13";
import { nextMonth, recurring } from "./detect.ts";

Deno.test("next month clamps to month end", () => {
  assertEquals(nextMonth("2027-01-31"), "2027-02-28");
  assertEquals(nextMonth("2028-01-31"), "2028-02-29");
  assertEquals(nextMonth("2026-03-31"), "2026-04-30");
  assertEquals(nextMonth("2026-12-15"), "2027-01-15");
});

Deno.test("monthly debit on the 31st renews on Feb 28, not Mar 3", () => {
  const t = (date: string) => ({ date, amount: -9.99, currency: "GBP", merchant: "Netflix", pending: false });
  const [item] = recurring([t("2026-12-31"), t("2027-01-31")], new Set());
  assertEquals(item.next_renewal_date, "2027-02-28");
});
