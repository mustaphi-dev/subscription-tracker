# Subtracker

Track subscriptions, free trials, BNPL payments, and bank balances. Built with Flutter and Supabase.

## Run the app

```sh
flutter pub get
flutter run
```

To use your own Supabase project: `cp env.example.json env.json`, fill it in, then run `flutter run --dart-define-from-file=env.json`.

## Backend setup

```sh
supabase link --project-ref <ref>
supabase db push
supabase secrets set ENABLE_BANKING_APP_ID=… ENABLE_BANKING_PRIVATE_KEY="$(cat enablebanking.pem)" ANTHROPIC_API_KEY=… \
  INBOUND_WEBHOOK_SECRET=… FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy
```

Then add the cron secrets in the Supabase SQL editor:

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');
select vault.create_secret('<service_role_key>', 'service_key');
```

Bank linking is offered per country. Each bank-data provider is one file in `supabase/functions/bank-sync/aggregators/`; add it to `AGGREGATORS` in `index.ts` and its country to `bankLinkingCountries` in `lib/countries.dart`. UK banks link through [Enable Banking](https://enablebanking.com): create an application in its Control Panel with the redirect URL `https://<ref>.supabase.co/functions/v1/bank-sync/callback`, and use its application id and private key above. The key must be PKCS#8 (`-----BEGIN PRIVATE KEY-----`); convert a PKCS#1 key with `openssl pkcs8 -topk8 -nocrypt -in key.pem -out enablebanking.pem`. Until you sign Enable Banking's agreement the app is in restricted mode and can only read accounts you've linked to it in the Control Panel. Older GoCardless links keep syncing if `GOCARDLESS_SECRET_ID` and `GOCARDLESS_SECRET_KEY` are still set.

Provider tests: `deno test --allow-env supabase/functions/bank-sync/aggregators/`.

Push notifications: run `flutterfire configure` and upload your APNs key to Firebase.

## Tests

```sh
flutter test
psql "$DB_URL" -f supabase/tests/money_test.sql
```
