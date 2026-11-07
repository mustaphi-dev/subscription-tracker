import 'dart:async';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

double? _d(Object? v) => v == null ? null : (v as num).toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

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

  /// When money next leaves (or arrives). Trials: the conversion moment.
  DateTime? get dueAt => isTrial ? trialEnd : nextRenewal;

  /// The amount that will actually be charged next, in original currency.
  double get chargeAmount => isTrial ? (postTrialAmount ?? 0) : amount;

  /// Normalised monthly value in base currency.
  double get monthlyBase {
    final b = baseAmount ?? 0;
    return switch (cycle) { 'weekly' => b * 52 / 12, 'quarterly' => b / 3, 'yearly' => b / 12, 'once' => 0, _ => b };
  }

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

DateTime _addMonths(DateTime d, int n) {
  final first = DateTime(d.year, d.month + n, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

/// Every projected charge/income in [from, to). Trials charge from trialEnd and keep renewing,
/// installments stop after the remaining payments.
List<Charge> chargesBetween(Iterable<FinancialItem> items, DateTime from, DateTime to) {
  final out = <Charge>[];
  for (final i in items) {
    if (i.status != 'active' && i.status != 'pending_confirmation') continue;
    final start = i.dueAt;
    if (start == null) continue;
    final value = (i.baseAmount ?? i.chargeAmount) * (i.type == 'income' ? 1 : -1);
    final remaining = i.type == 'installment' && i.installTotal != null ? i.installTotal! - i.installPaid : null;
    for (var k = 0; remaining == null || k < remaining; k++) {
      final d = switch (i.cycle) {
        'weekly' => start.add(Duration(days: 7 * k)),
        'quarterly' => _addMonths(start, 3 * k),
        'yearly' => _addMonths(start, 12 * k),
        'once' => k == 0 ? start : null,
        _ => _addMonths(start, k),
      };
      if (d == null || !d.isBefore(to)) break;
      if (!d.isBefore(from)) out.add(Charge(i, d, value));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
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

final baseCurrencyProvider = StreamProvider<String>((ref) {
  ref.watch(uidProvider);
  final uid = db.auth.currentUser?.id;
  if (uid == null) return Stream.value('GBP');
  return db.from('profiles').stream(primaryKey: ['id']).eq('id', uid).map(
        (rows) => rows.isEmpty ? 'GBP' : isoCurrency(rows.first['global_base_currency'] as String?),
      );
});

/// [raw] as a clean ISO 4217 code, or GBP if it isn't one (so money never renders as "G12.00").
String isoCurrency(String? raw) {
  final c = (raw ?? '').trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(c) ? c : 'GBP';
}

/// The user's country code (null until picked after sign-up).
final countryProvider = StreamProvider<String?>((ref) {
  ref.watch(uidProvider);
  final uid = db.auth.currentUser?.id;
  if (uid == null) return Stream.value(null);
  return db.from('profiles').stream(primaryKey: ['id']).eq('id', uid).map(
        (rows) => rows.isEmpty ? null : rows.first['country'] as String?,
      );
});

/// True once we know the signed-in user hasn't picked a country yet; drives the router.
final needsCountry = ValueNotifier(false);

Future<void> refreshNeedsCountry() async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) {
    needsCountry.value = false;
    return;
  }
  try {
    final row = await db.from('profiles').select('country').eq('id', uid).maybeSingle();
    needsCountry.value = row != null && row['country'] == null;
  } catch (_) {
    // Offline or schema not migrated yet: don't trap the user on the picker.
    needsCountry.value = false;
  }
}

/// Saves the country; on first pick also sets the display currency to the local one.
Future<void> setCountry(String code, {String? currency}) async {
  await db.from('profiles').update({
    'country': code,
    'global_base_currency': ?currency,
  }).eq('id', db.auth.currentUser!.id);
  needsCountry.value = false;
}

/// The user's personal forwarding address, e.g. adams-k7f2x@trywince.app.
final inboundAddressProvider = FutureProvider<String?>((ref) async {
  ref.watch(uidProvider);
  final r = await db.from('profiles').select('inbound_parse_email').maybeSingle();
  return r?['inbound_parse_email'] as String?;
});

final sourcesProvider = StreamProvider<List<PaymentSource>>((ref) {
  ref.watch(uidProvider);
  return db.from('payment_sources').stream(primaryKey: ['id']).map((r) => r.map(PaymentSource.new).toList());
});

final itemsProvider = StreamProvider<List<FinancialItem>>((ref) {
  ref.watch(uidProvider);
  return db.from('financial_items').stream(primaryKey: ['id']).map((rows) {
    final items = rows.map(FinancialItem.new).where((i) => i.status != 'cancelled').toList();
    final far = DateTime(9999);
    items.sort((a, b) => (a.dueAt ?? far).compareTo(b.dueAt ?? far));
    return items;
  });
});

final shortfallProvider = FutureProvider<List<Shortfall>>((ref) async {
  // Recompute whenever balances or items change.
  await ref.watch(sourcesProvider.future);
  await ref.watch(itemsProvider.future);
  final rows = await db.from('shortfall_check').select();
  return rows.map(Shortfall.new).toList();
});

/// 1 Hz clock for live countdowns.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

class _Pick extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

const typeFilters = [null, 'free_trial', 'subscription', 'installment', 'income'];
final typeFilterProvider = NotifierProvider<_Pick, int>(_Pick.new);

final filteredItemsProvider = Provider<List<FinancialItem>>((ref) {
  final items = ref.watch(itemsProvider).value ?? [];
  final t = typeFilters[ref.watch(typeFilterProvider)];
  return items
      .where((i) => i.status == 'active' || i.status == 'pending_confirmation')
      .where((i) => t == null || i.type == t)
      .toList();
});

// ───────── Actions ─────────

// Postgrest builders are lazy: nothing is sent until awaited, so await here rather than trust callers.
Future<void> setItemStatus(String id, String status) async =>
    await db.from('financial_items').update({'status': status}).eq('id', id);

Future<void> setBaseCurrency(String ccy) async =>
    await db.from('profiles').update({'global_base_currency': ccy}).eq('id', db.auth.currentUser!.id);

Future<void> addItem(Map<String, dynamic> row) async => await db.from('financial_items').insert(row);

/// Banks the user can link in their country (empty where bank sync isn't offered).
final banksProvider = FutureProvider<List<String>>((ref) async {
  final country = await ref.watch(countryProvider.future);
  if (country == null) return [];
  final res = await db.functions.invoke('bank-sync/banks');
  return [for (final b in res.data['banks'] as List) b['name'] as String];
});

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


/// Every tracked item (cancelled ones too) as export rows, header first.
List<List<Object?>> itemsTable(List<FinancialItem> items) => [
      ['merchant', 'type', 'status', 'amount', 'currency', 'cycle', 'next_renewal', 'trial_end', 'post_trial_amount', 'total_spent', 'added'],
      for (final i in items)
        [i.merchant, i.type, i.status, i.amount, i.currency, i.cycle, i.nextRenewal, i.trialEnd, i.postTrialAmount, i.totalSpent, i.createdAt]
            .map((v) => v is DateTime ? v.toIso8601String().substring(0, 10) : v)
            .toList(),
    ];

String itemsCsv(List<FinancialItem> items) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return itemsTable(items).map((r) => r.map(cell).join(',')).join('\n');
}

List<int> itemsXlsx(List<FinancialItem> items) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  for (final r in itemsTable(items)) {
    sheet.appendRow([for (final v in r) v is num ? DoubleCellValue(v.toDouble()) : TextCellValue('${v ?? ''}')]);
  }
  return book.encode()!;
}
