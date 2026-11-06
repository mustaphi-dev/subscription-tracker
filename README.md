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
supabase secrets set GOCARDLESS_SECRET_ID=… GOCARDLESS_SECRET_KEY=… ANTHROPIC_API_KEY=… \
  INBOUND_WEBHOOK_SECRET=… FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy
```

Then add the cron secrets in the Supabase SQL editor:

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');
select vault.create_secret('<service_role_key>', 'service_key');
```

Bank linking is offered per country. Each bank-data provider is one file in `supabase/functions/bank-sync/aggregators/`; add it to `AGGREGATORS` in `index.ts` and its country to `bankLinkingCountries` in `lib/countries.dart`. GoCardless Bank Account Data (UK) is closed to new sign-ups, so new projects need another provider.

Push notifications: run `flutterfire configure` and upload your APNs key to Firebase.

## Tests

```sh
flutter test
psql "$DB_URL" -f supabase/tests/money_test.sql
```
