// Encrypted storage for per-connection OAuth tokens (bank_tokens table).
// BANK_TOKEN_KEY is 32 random bytes, base64: `openssl rand -base64 32`.
import { admin, env } from "../_shared/mod.ts";

export type Tokens = { access: string; refresh: string | null; expiresAt: number };

export interface TokenStore {
  get(id: string): Promise<Tokens | null>;
  put(id: string, t: Tokens): Promise<void>;
  remove(id: string): Promise<void>;
}

let key: CryptoKey | null = null;
async function aes() {
  if (key) return key;
  const raw = Uint8Array.from(atob(env("BANK_TOKEN_KEY")), (c) => c.charCodeAt(0));
  if (raw.length !== 32) throw new Error("BANK_TOKEN_KEY must be 32 bytes, base64-encoded");
  key = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
  return key;
}

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export async function seal(t: Tokens): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new TextEncoder().encode(JSON.stringify(t));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aes(), data));
  return `${b64(iv)}.${b64(ct)}`;
}

export async function open(sealed: string): Promise<Tokens> {
  const [iv, ct] = sealed.split(".").map(unb64);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, await aes(), ct);
  return JSON.parse(new TextDecoder().decode(pt));
}

export const dbTokens: TokenStore = {
  async get(id) {
    const { data } = await admin.from("bank_tokens").select("ciphertext").eq("external_id", id).maybeSingle();
    return data ? await open(data.ciphertext) : null;
  },
  async put(id, t) {
    const { error } = await admin.from("bank_tokens").upsert({
      external_id: id, ciphertext: await seal(t),
      expires_at: new Date(t.expiresAt).toISOString(), updated_at: new Date().toISOString(),
    });
    if (error) throw new Error(`bank_tokens: ${error.message}`);
  },
  async remove(id) {
    await admin.from("bank_tokens").delete().eq("external_id", id);
  },
};
