// One bank-data provider (GoCardless, Enable Banking, TrueLayer, Mono…) behind a common shape,
// so adding a country means adding a file here, not touching detection or the app.

export type LinkStatus = "pending" | "linked" | "rejected" | "expired";

export type Account = { id: string; name: string; balance: number; currency: string };

/** A transaction in provider-neutral form. Debits are negative. */
export type Txn = { date: string; amount: number; currency: string; merchant: string; pending: boolean };

export interface Aggregator {
  /** Stored in bank_connections.aggregator. */
  id: string;
  /** ISO country codes this provider links banks in. */
  countries: string[];
  /** App-facing bank keys (e.g. "lloyds") this provider can connect. */
  institutions: string[];
  /** Start a consent session; returns the provider's id for it and the URL the user opens. */
  createLink(o: { institution: string; reference: string; redirect: string }): Promise<{ externalId: string; link: string }>;
  /** Current state of a consent and the account ids it covers. */
  status(externalId: string): Promise<{ status: LinkStatus; accounts: string[] }>;
  /** Balance and recent transactions for one account. */
  fetchAccount(accountId: string): Promise<{ account: Account; transactions: Txn[] }>;
}
