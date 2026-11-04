# Subtracker

Flutter + Supabase tracker for subscriptions, free trials, BNPL installments, income and live balances across Revolut, Wise, Lloyds and PayPal.

```
supabase/migrations/…_init.sql   schema, RLS, to_base() FX, shortfall_check view, roll_forward_items(), cron
supabase/functions/
  bank-sync/            GoCardless Bank Account Data: connect → callback → sync, £0/£1 trial + recurring detection
  parse-trial-receipt/  Claude extraction from screenshot (app) or forwarded email (Postmark inbound)
  fx-sync/              6-hourly rates (open.er-api.com, keyless, covers GHS)
  dispatch-alerts/      FCM: trial 7d / 3d / 24h + shortfall
supabase/tests/money_test.sql    FX, shortfall, roll-forward, RLS asserts
lib/
  glass.dart      LiquidGlassCard, MeshBackground, chips, ticker, tokens
  lock.dart       Face ID + 6-digit PIN gate, salted SHA-256 PIN, app-switcher shield
  data.dart       models + Riverpod providers (Supabase realtime streams)
  home.dart       shell, glass nav, dashboard, hero, carousels, shortfall banner, timeline, add sheet
  item_tile.dart  expandable subscription / trial / installment tiles
  screens.dart    Trials & Calendar, Accounts, Analytics, sign-in, manual form, confirm-trial
  push.dart       FCM, local notifications, home-screen widget feed
```

## Setup

**Supabase**
```sh
supabase link --project-ref <ref>
supabase db push
supabase secrets set GOCARDLESS_SECRET_ID=… GOCARDLESS_SECRET_KEY=… ANTHROPIC_API_KEY=… \
  INBOUND_WEBHOOK_SECRET=$(openssl rand -hex 24) FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy
```
Then in the SQL editor, put the cron targets in Vault:
```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');
select vault.create_secret('<service_role_key>', 'service_key');
```
Test: `psql "$DB_URL" -f supabase/tests/money_test.sql` (runs in a transaction and rolls back).

**Inbound email:** point a Postmark inbound domain (`inbound.subtracker.app`, see `handle_new_user()`) at
`https://<ref>.supabase.co/functions/v1/parse-trial-receipt?secret=<INBOUND_WEBHOOK_SECRET>`.

**Firebase:** `flutterfire configure` (adds google-services.json / GoogleService-Info.plist). Upload your APNs key in Firebase.

**iOS widget:** in Xcode, add a Widget Extension target named `TrialWidget`, replace its Swift file with
`ios/TrialWidget/TrialWidget.swift`, and enable App Group `group.com.lovefist.subtracker` on Runner and TrialWidget.

**Run**
```sh
flutter run   # or Android Studio / VS Code Run; project URL + publishable key default in lib/main.dart
# point at another project: cp env.example.json env.json, edit, flutter run --dart-define-from-file=env.json
```
