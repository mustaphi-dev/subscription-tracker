# Wince

Track subscriptions, free trials, BNPL payments, and bank balances. Built with Flutter and Supabase.

## Run the app

```sh
flutter pub get
flutter run
```

Copy `env.example.json` to `env.json`, fill it in, then run `flutter run --dart-define-from-file=env.json` (VS Code's launch config already passes it). `LOGO_DEV_KEY` is your logo.dev publishable key; without it, merchant and bank logos fall back to letter tiles.

To see the onboarding again, sign out and add `--dart-define=REPLAY_ONBOARDING=true`. That forgets on every launch that onboarding was seen. Deleting the app isn't enough on iOS, because the keychain keeps the flag. Signed-in users always skip onboarding.

## Backend setup

```sh
supabase link --project-ref <ref>
supabase db push
supabase secrets set TRUELAYER_CLIENT_ID=… TRUELAYER_CLIENT_SECRET=… BANK_TOKEN_KEY="$(openssl rand -base64 32)" ANTHROPIC_API_KEY=… \
  INBOUND_WEBHOOK_SECRET=… FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy
```

Then add the cron secrets in the Supabase SQL editor:

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');
select vault.create_secret('<sb_secret_… key>', 'service_key');
```

Use a secret key (`sb_secret_…`, Project Settings → API Keys). The legacy `eyJ…` service_role key is rejected by the functions on newer projects.

Bank linking is offered per country. Each bank-data provider is one file in `supabase/functions/bank-sync/aggregators/` (TrueLayer is the only one, called directly from `index.ts`); its countries must match `bankLinkingCountries` in `lib/countries.dart`. UK banks link through [TrueLayer](https://console.truelayer.com): in its Console, add the redirect URI `https://<ref>.supabase.co/functions/v1/bank-sync/callback` and enable the Data API scopes `info accounts balance transactions offline_access`, then set the client id and secret above. `BANK_TOKEN_KEY` encrypts users' bank tokens at rest; set it once and keep it, because changing it disconnects every TrueLayer link. To test against TrueLayer's sandbox, use the sandbox client id and secret and also set `TRUELAYER_ENV=sandbox`: the bank list shows only Mock Bank, and you sign in with `john` / `doe`.

Email forwarding: each user gets an address like `adams-k7f2x@trywince.app`. Cloudflare Email Routing catches all mail to the domain and hands it to the Email Worker in `workers/inbound-email/`, which posts it to `parse-trial-receipt`. To set it up, deploy the worker and give both sides the same secret:

```sh
cd workers/inbound-email && npm install && npx wrangler deploy
SECRET=$(openssl rand -hex 32)
echo "$SECRET" | npx wrangler secret put INBOUND_SECRET
supabase secrets set INBOUND_WEBHOOK_SECRET="$SECRET"
```

Then in Cloudflare → Email Routing, set the catch-all to *Send to a Worker* → `wince-inbound-email`. Addresses you read yourself (e.g. `hello@`) need their own rule above it, or the worker swallows them. Worker self-check: `node workers/inbound-email/check.mjs`. Receipts are read by Claude Haiku; set `ANTHROPIC_MODEL` to use another model.

Bank-sync tests: `cd supabase/functions/bank-sync && deno test -A`.

Push notifications: run `flutterfire configure` and upload your APNs key to Firebase.

## Tests

```sh
flutter test
psql "$DB_URL" -f supabase/tests/money_test.sql
```
