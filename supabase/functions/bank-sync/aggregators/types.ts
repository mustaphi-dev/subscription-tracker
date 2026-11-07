// One bank-data provider (TrueLayer today) behind a common shape,
// so adding a country means adding a file here, not touching detection or the app.

export type LinkStatus = "pending" | "linked" | "rejected" | "expired";

export type Bank = { name: string; logo?: string };

export type Account = { id: string; name: string; balance: number; currency: string };

/** A transaction in provider-neutral form. Debits are negative. */
export type Txn = { date: string; amount: number; currency: string; merchant: string; pending: boolean };

export interface Aggregator {
  /** Stored in bank_connections.aggregator. */
  id: string;
  /** ISO country codes new links go through this provider for. Empty = existing links only. */
  countries: string[];
  listBanks(country: string): Promise<Bank[]>;
  /** Start a consent; returns the provider's id for it and the URL the user opens. */
  createLink(o: { bank: string; country: string; reference: string; redirect: string }): Promise<{ externalId: string; link: string }>;
  /** Finish a consent from the redirect's query string; [redirect] is the one createLink was given. May swap in a new id. */
  completeLink(externalId: string, query: URLSearchParams, redirect: string): Promise<{ externalId: string; status: LinkStatus }>;
  status(externalId: string): Promise<{ status: LinkStatus; accounts: string[] }>;
  /** Balance and recent transactions for one account under the consent [externalId]. */
  fetchAccount(externalId: string, accountId: string): Promise<{ account: Account; transactions: Txn[] }>;
}
