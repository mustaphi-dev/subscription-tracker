-- OAuth tokens for providers that hand out per-user tokens (TrueLayer). Server-only:
-- RLS on with no policies, so only the service role reads it. Values are AES-GCM
-- encrypted by the edge function with BANK_TOKEN_KEY before they get here.
create table public.bank_tokens (
  external_id text primary key,
  ciphertext text not null,
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.bank_tokens enable row level security;
