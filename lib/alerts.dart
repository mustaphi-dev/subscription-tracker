import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatars.dart';
import 'brands.dart';
import 'data.dart';
import 'item_tile.dart';
import 'ui.dart';

/// Notifications the user cleared, kept on the device. Keys include the due date, so the next
/// renewal or a new shortfall shows up again.
class _Dismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    storage.read(key: 'dismissed_alerts').then((v) {
      if (v != null) state = {...state, ...(jsonDecode(v) as List).cast<String>()};
    }).catchError((_) {}); // unreadable storage just means nothing was cleared yet
    return {};
  }

  // ponytail: keys accumulate forever; prune past due dates if this list ever grows noticeably.
  void addAll(Iterable<String> keys) {
    state = {...state, ...keys};
    storage.write(key: 'dismissed_alerts', value: jsonEncode(state.toList()));
  }

  void removeAll(Iterable<String> keys) {
    state = state.difference(keys.toSet());
    storage.write(key: 'dismissed_alerts', value: jsonEncode(state.toList()));
  }
}

final _dismissedAlerts = NotifierProvider<_Dismissed, Set<String>>(_Dismissed.new);

typedef Alert = ({String key, String logo, Color color, String title, String sub});

/// What the bell shows: low balances, trials ending within a week, and payments due in 24 hours.
final alertsProvider = Provider<List<Alert>>((ref) {
  final hidden = ref.watch(_dismissedAlerts);
  final banks = {for (final a in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) a.id: a.bank};
  final now = DateTime.now();
  final items = (ref.watch(itemsProvider).value ?? []).where((i) => i.status == 'active' && i.dueAt != null && i.dueAt!.isAfter(now));
  final all = <Alert>[
    for (final s in ref.watch(shortfallProvider).value ?? <Shortfall>[])
      (
        key: 'short:${s.sourceId}:${s.due}',
        logo: banks[s.sourceId] ?? s.provider,
        color: kCrimson,
        title: 'Top up ${banks[s.sourceId] ?? 'account'} by ${money(s.shortfall, s.currency)}',
        sub: '${money(s.due, s.currency)} due ${s.days == 0 ? 'today' : 'within ${s.days} day${s.days == 1 ? '' : 's'}'}, balance ${money(s.balance, s.currency)}',
      ),
    // Same window as the push reminders.
    for (final i in items.where((i) => i.isTrial && i.trialEnd!.difference(now).inDays < 7))
      (
        key: 'trial:${i.id}:${i.trialEnd!.toIso8601String()}',
        logo: i.merchant,
        color: kAmber,
        title: '${i.merchant} trial ends ${dueLabel(i.trialEnd!).toLowerCase()}',
        sub: i.postTrialAmount == null ? 'Charge after the trial is unknown' : 'Then ${priceTag(i.postTrialAmount!, i.currency, i.cycle)}',
      ),
    for (final i in items.where((i) => !i.isTrial && i.type != 'income' && i.dueSoon))
      (
        key: 'due:${i.id}:${i.dueAt!.toIso8601String()}',
        logo: i.merchant,
        color: kAccent,
        title: '${i.merchant} takes ${money(i.chargeAmount, i.currency)} ${dueLabel(i.dueAt!).toLowerCase()}',
        sub: banks[i.sourceId] ?? 'Payment due',
      ),
  ];
  return all.where((a) => !hidden.contains(a.key)).toList();
});

/// The bell's sheet: only things that need attention, one line each. Swipe or tap × to clear.
class AlertsSheet extends ConsumerWidget {
  const AlertsSheet({super.key, required this.scroll});
  final ScrollController scroll;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    void clear(Iterable<String> keys) {
      final gone = keys.toList(), notifier = ref.read(_dismissedAlerts.notifier);
      notifier.addAll(gone);
      showToast(context, gone.length == 1 ? 'Notification cleared' : '${gone.length} notifications cleared',
          closeSheets: false, onUndo: () => notifier.removeAll(gone));
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Notifications', style: display(20))),
            if (alerts.isNotEmpty) TextButton(onPressed: () => clear(alerts.map((a) => a.key)), child: const Text('Clear all')),
          ]),
        ),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('You\'re all caught up.', style: TextStyle(color: kMuted)),
          ),
        for (final a in alerts)
          Dismissible(
            key: ValueKey(a.key),
            onDismissed: (_) => clear([a.key]),
            background: Container(
              color: kCrimson.withValues(alpha: 0.15),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(CupertinoIcons.trash, color: kCrimson, size: 20),
            ),
            direction: DismissDirection.endToStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(children: [
                MerchantAvatar(a.logo, size: 40, dot: a.color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    Text(a.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                  ]),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(CupertinoIcons.xmark, size: 16, color: kMuted),
                  onPressed: () => clear([a.key]),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}
