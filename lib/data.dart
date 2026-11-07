import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


SupabaseClient get db => Supabase.instance.client;

/// Keychain / Keystore: the PIN, onboarding, last email and cleared alerts all live here.
const storage = FlutterSecureStorage();

double? _d(Object? v) => v == null ? null : (v as num).toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// [raw] as a clean ISO 4217 code, or GBP if it isn't one (so money never renders as "G12.00").
String isoCurrency(String? raw) {
  final c = (raw ?? '').trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(c) ? c : 'GBP';
}

// ───────── Vocabulary ─────────

/// What an item type is called on the Home tabs, in the add form, in its details and on the chart.
typedef ItemType = ({String tab, String form, String name, String chart});

/// In the add form's order.
const itemTypes = <String, ItemType>{
  'subscription': (tab: 'Subs', form: 'Subscription', name: 'Subscription', chart: 'Subscriptions'),
  'free_trial': (tab: 'Trials', form: 'Trial', name: 'Free trial', chart: 'Trials (after conversion)'),
  'installment': (tab: 'Pay later', form: 'Pay later', name: 'Installment', chart: 'Pay later'),
  'income': (tab: 'Income', form: 'Income', name: 'Income', chart: 'Income'),
};

class Cycle {
  const Cycle(this.label, this.hint, this.per, {this.months = 0, this.days = 0});
  final String label, hint;

  /// Price suffix, e.g. `/mo`.
  final String per;
  final int months, days;

  /// The [k]th date from [start] (0 = [start]); null past a one-off's only date.
  DateTime? nth(DateTime start, int k) => months > 0
      ? _addMonths(start, months * k)
      : days > 0
          ? start.add(Duration(days: days * k))
          : k == 0
              ? start
              : null;

  /// How many times it falls in an average month (0 for one-offs).
  double get perMonth => months > 0 ? 1 / months : days > 0 ? 52 / 12 * (7 / days) : 0;
}

const cycles = {
  'weekly': Cycle('Weekly', 'Every 7 days', '/wk', days: 7),
  'monthly': Cycle('Monthly', 'Same date each month', '/mo', months: 1),
  'quarterly': Cycle('Quarterly', 'Every 3 months', '/qtr', months: 3),
  'yearly': Cycle('Yearly', 'Once a year', '/yr', months: 12),
  'once': Cycle('One-off', 'Doesn\'t repeat', ''),
};

/// Month arithmetic that clamps to month end: Jan 31 + 1 = Feb 28.
DateTime _addMonths(DateTime d, int n) {
  final first = DateTime(d.year, d.month + n, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

/// Short price for chips: symbol, no `.00` on whole amounts, optional cycle. `£20/mo`, `GH₵78.50/qtr`.
String priceTag(num amount, String ccy, [String? cycle]) {
  final symbol = NumberFormat.simpleCurrency(locale: 'en_GB', name: ccy).currencySymbol;
  final n = NumberFormat(amount % 1 == 0 ? '#,##0' : '#,##0.00', 'en_GB').format(amount);
  return '$symbol$n${cycles[cycle]?.per ?? ''}';
}

// ───────── Models ─────────

class Profile {
  Profile(Map<String, dynamic> m)
      : baseCurrency = isoCurrency(m['global_base_currency'] as String?),
        country = m['country'],
        inboundEmail = m['inbound_parse_email'];
  final String baseCurrency;

  /// Null until picked after sign-up.
  final String? country;

  /// The personal forwarding address, e.g. adams-k7f2x@trywince.app.
  final String? inboundEmail;
}

class PaymentSource {
  PaymentSource(Map<String, dynamic> m)
      : id = m['id'],
        provider = m['provider'],
        name = m['account_name'],
        balance = _d(m['current_balance']) ?? 0,
        currency = m['currency'],
        baseBalance = _d(m['gbp_equivalent_balance']),
        lastSynced = _date(m['last_synced_at']),
        institution = m['institution'],
        isManual = m['is_manual'] ?? false;
  final String id, provider, name, currency;
  final String? institution;
  final bool isManual;
  final double balance;
  final double? baseBalance;
  final DateTime? lastSynced;
}

class FinancialItem {
  FinancialItem(Map<String, dynamic> m)
      : id = m['id'],
        sourceId = m['payment_source_id'],
        type = m['item_type'],
        merchant = m['merchant_name'],
        amount = _d(m['original_amount']) ?? 0,
        currency = m['original_currency'],
        baseAmount = _d(m['gbp_equivalent_amount']),
        postTrialAmount = _d(m['post_trial_amount']),
        nextRenewal = _date(m['next_renewal_date']),
        trialEnd = _date(m['trial_end_date']),
        cycle = m['billing_cycle'],
        installTotal = m['installment_total_count'],
        installPaid = m['installment_paid_count'] ?? 0,
        installRemaining = _d(m['installment_remaining_balance']),
        cancelUrl = m['cancellation_url'],
        status = m['status'],
        detectedVia = m['auto_detected_via'],
        totalSpent = _d(m['total_spent']) ?? 0,
        createdAt = _date(m['created_at']);

  final String id, type, merchant, currency, cycle, status, detectedVia;
  final String? sourceId, cancelUrl;
  final double amount, totalSpent;
  final double? baseAmount, postTrialAmount, installRemaining;
  final DateTime? nextRenewal, trialEnd, createdAt;
  final int? installTotal;
  final int installPaid;

  bool get isTrial => type == 'free_trial';

  /// Counts toward totals and projections: active, or a detected trial waiting to be confirmed.
  bool get isLive => status == 'active' || status == 'pending_confirmation';

  bool get isRunningTrial => isTrial && trialEnd != null && trialEnd!.isAfter(DateTime.now());

  /// Due within 24 hours, or already overdue.
  bool get dueSoon => dueAt != null && dueAt!.difference(DateTime.now()).inHours < 24;

  /// Unknown cycles bill monthly.
  Cycle get every => cycles[cycle] ?? cycles['monthly']!;

  /// When money next leaves (or arrives). Trials: the conversion moment.
  DateTime? get dueAt => isTrial ? trialEnd : nextRenewal;

  /// The amount that will actually be charged next, in original currency.
  double get chargeAmount => isTrial ? (postTrialAmount ?? 0) : amount;

  /// Normalised monthly value in base currency.
  double get monthlyBase => (baseAmount ?? 0) * every.perMonth;

  /// Date of the last installment, counted on from the next one by the cycle.
  DateTime? get finalPayment =>
      nextRenewal == null || (installTotal ?? 0) == 0 ? null : every.nth(nextRenewal!, installTotal! - installPaid - 1);

  /// Share of the trial already used, 0..1 (needs createdAt as the start).
  double get trialProgress {
    if (trialEnd == null || createdAt == null) return 0;
    final total = trialEnd!.difference(createdAt!).inMinutes;
    if (total <= 0) return 1;
    return (DateTime.now().difference(createdAt!).inMinutes / total).clamp(0, 1);
  }
}

/// One projected money movement. [amount] is in base currency; income is positive, charges negative.
class Charge {
  const Charge(this.item, this.date, this.amount);
  final FinancialItem item;
  final DateTime date;
  final double amount;
}

/// Every projected charge/income in [from, to). Trials charge from trialEnd and keep renewing,
/// installments stop after the remaining payments.
List<Charge> chargesBetween(Iterable<FinancialItem> items, DateTime from, DateTime to) {
  final out = <Charge>[];
  for (final i in items) {
    if (!i.isLive) continue;
    final start = i.dueAt;
    if (start == null) continue;
    final value = (i.baseAmount ?? i.chargeAmount) * (i.type == 'income' ? 1 : -1);
    final remaining = i.type == 'installment' && i.installTotal != null ? i.installTotal! - i.installPaid : null;
    for (var k = 0; remaining == null || k < remaining; k++) {
      final d = i.every.nth(start, k);
      if (d == null || !d.isBefore(to)) break;
      if (!d.isBefore(from)) out.add(Charge(i, d, value));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

extension ItemTotals on Iterable<FinancialItem> {
  double get monthlyOut => where((i) => i.type != 'income').fold(0.0, (s, i) => s + i.monthlyBase);
  double get monthlyIn => where((i) => i.type == 'income').fold(0.0, (s, i) => s + i.monthlyBase);
}

extension SourceTotals on Iterable<PaymentSource> {
  double get totalBase => fold(0.0, (s, a) => s + (a.baseBalance ?? 0));
}

extension ChargeTotals on Iterable<Charge> {
  /// What goes out, as a positive amount.
  double get spend => where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);
}

class Shortfall {
  Shortfall(Map<String, dynamic> m)
      : sourceId = m['payment_source_id'],
        provider = m['provider'],
        due = _d(m['due_amount']) ?? 0,
        balance = _d(m['balance']) ?? 0,
        shortfall = _d(m['shortfall']) ?? 0,
        days = m['days_until_first'] ?? 0,
        currency = isoCurrency(m['currency'] as String?);
  final String sourceId, provider, currency;
  final double due, balance, shortfall;
  final int days;
}

// ───────── Providers ─────────

final authProvider = StreamProvider<AuthState>((ref) => db.auth.onAuthStateChange);

/// The signed-in user's id. Only changes on sign-in/out, so token refreshes (e.g. on resume) don't reload data.
final uidProvider = Provider<String?>((ref) => ref.watch(authProvider).value?.session?.user.id ?? db.auth.currentUser?.id);

/// The signed-in user's profile row, live. Null when signed out or before the row exists.
final profileProvider = StreamProvider<Profile?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return db.from('profiles').stream(primaryKey: ['id']).eq('id', uid).map((rows) => rows.isEmpty ? null : Profile(rows.first));
});

/// The display currency every total is shown in.
final baseProvider = Provider<String>((ref) => ref.watch(profileProvider.select((p) => p.value?.baseCurrency)) ?? isoCurrency(null));

/// True once the signed-in user's profile has loaded without a country; the router's Listenable.
/// App sets it from [profileProvider].
final needsCountry = ValueNotifier(false);

final sourcesProvider = StreamProvider<List<PaymentSource>>((ref) {
  ref.watch(uidProvider);
  return db.from('payment_sources').stream(primaryKey: ['id']).map((r) => r.map(PaymentSource.new).toList());
});

/// Everything not cancelled, soonest due first.
final itemsProvider = StreamProvider<List<FinancialItem>>((ref) {
  ref.watch(uidProvider);
  return db.from('financial_items').stream(primaryKey: ['id']).map((rows) {
    final items = rows.map(FinancialItem.new).where((i) => i.status != 'cancelled').toList();
    final far = DateTime(9999);
    items.sort((a, b) => (a.dueAt ?? far).compareTo(b.dueAt ?? far));
    return items;
  });
});

final liveItemsProvider = Provider<List<FinancialItem>>((ref) => (ref.watch(itemsProvider).value ?? []).where((i) => i.isLive).toList());

final shortfallProvider = FutureProvider<List<Shortfall>>((ref) async {
  // Recompute whenever balances or items change.
  await ref.watch(sourcesProvider.future);
  await ref.watch(itemsProvider.future);
  final rows = await db.from('shortfall_check').select();
  return rows.map(Shortfall.new).toList();
});

final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// A value the UI sets and reads back.
class Pick<T> extends Notifier<T> {
  Pick(this._initial);
  final T _initial;
  @override
  T build() => _initial;
  void set(T v) => state = v;
}

/// Home's type tabs, in order; null = all.
const typeFilters = [null, 'free_trial', 'subscription', 'installment', 'income'];
final typeFilterProvider = NotifierProvider<Pick<String?>, String?>(() => Pick(null));

final filteredItemsProvider = Provider<List<FinancialItem>>((ref) {
  final t = ref.watch(typeFilterProvider);
  return ref.watch(liveItemsProvider).where((i) => t == null || i.type == t).toList();
});

/// Banks the user can link in their country (empty where bank sync isn't offered).
final banksProvider = FutureProvider<List<String>>((ref) async {
  final country = await ref.watch(profileProvider.selectAsync((p) => p?.country));
  if (country == null) return [];
  final res = await db.functions.invoke('bank-sync/banks');
  return [for (final b in res.data['banks'] as List) b['name'] as String];
});

// ───────── Actions ─────────

// Postgrest builders are lazy: nothing is sent until awaited, so await here rather than trust callers.
Future<void> updateProfile(Map<String, Object?> fields) async =>
    await db.from('profiles').update(fields).eq('id', db.auth.currentUser!.id);

/// Saves the country; on first pick also sets the display currency to the local one.
Future<void> setCountry(String code, {String? currency}) => updateProfile({'country': code, 'global_base_currency': ?currency});

Future<void> setBaseCurrency(String ccy) => updateProfile({'global_base_currency': ccy});

Future<void> setItemStatus(String id, String status) async =>
    await db.from('financial_items').update({'status': status}).eq('id', id);

Future<void> addItem(Map<String, dynamic> row) async => await db.from('financial_items').insert(row);

/// Starts a consent with [bank] (a name from [banksProvider]); returns the bank's URL to open.
Future<String> connectBank(String bank) async {
  final res = await db.functions.invoke('bank-sync/connect', body: {'bank': bank});
  return res.data['link'] as String;
}

Future<void> syncBanks() => db.functions.invoke('bank-sync/sync');

/// Unlinks an Open Banking bank on the server, so the next sync doesn't bring its accounts back.
Future<void> unlinkBank(String bank) => db.functions.invoke('bank-sync/disconnect', body: {'bank': bank});

Future<void> removeAccounts(Iterable<String> ids) async => await db.from('payment_sources').delete().inFilter('id', ids.toList());

Future<Map<String, dynamic>> parseReceipt(Map<String, dynamic> body) async =>
    (await db.functions.invoke('parse-trial-receipt', body: body)).data as Map<String, dynamic>;
