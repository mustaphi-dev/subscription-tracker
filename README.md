# Subtracker

Track subscriptions, free trials, BNPL payments, and bank balances. Built with Flutter and Supabase.

## Run the app

```sh
flutter pub get
flutter run
```

Copy `env.example.json` to `env.json`, fill it in, then run `flutter run --dart-define-from-file=env.json` (VS Code's launch config already passes it). `LOGO_DEV_KEY` is your logo.dev publishable key; without it, merchant and bank logos fall back to letter tiles.

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
select vault.create_secret('<service_role_key>', 'service_key');
```

Bank linking is offered per country. Each bank-data provider is one file in `supabase/functions/bank-sync/aggregators/`; add it to `AGGREGATORS` in `index.ts` and its country to `bankLinkingCountries` in `lib/countries.dart`. UK banks link through [TrueLayer](https://console.truelayer.com): in its Console, add the redirect URI `https://<ref>.supabase.co/functions/v1/bank-sync/callback` and enable the Data API scopes `info accounts balance transactions offline_access`, then set the client id and secret above. `BANK_TOKEN_KEY` encrypts users' bank tokens at rest; set it once and keep it, because changing it disconnects every TrueLayer link. To test against TrueLayer's sandbox, use the sandbox client id and secret and also set `TRUELAYER_ENV=sandbox`: the bank list shows only Mock Bank, and you sign in with `john` / `doe`. Enable Banking (EU banks) is wired in but takes no new links until its production access is sorted; its secrets are `ENABLE_BANKING_APP_ID` and `ENABLE_BANKING_PRIVATE_KEY` (a PKCS#8 key). Older GoCardless links keep syncing if `GOCARDLESS_SECRET_ID` and `GOCARDLESS_SECRET_KEY` are still set.

Provider tests: `deno test --allow-env supabase/functions/bank-sync/aggregators/`.

Push notifications: run `flutterfire configure` and upload your APNs key to Firebase.

## Tests

```sh
flutter test
psql "$DB_URL" -f supabase/tests/money_test.sql
```
