import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'brands.dart';
import 'data.dart';
import 'ui.dart';

/// Next trials and subscription renewals, soonest first. The ring around each logo shows how much
/// of the period has gone: trials from when they were added, subscriptions from the last renewal.
Future<void> updateTrialWidget(List<FinancialItem> items, String base) async {
  final now = DateTime.now();
  final due = (items
          .where((i) => i.isLive && (i.isRunningTrial || (i.type == 'subscription' && (i.nextRenewal?.isAfter(now) ?? false))))
          .toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!)))
      .take(5)
      .map((i) => {
            'name': i.merchant,
            'ends_at': i.dueAt!.millisecondsSinceEpoch,
            'starts_at': (i.isTrial ? i.createdAt : i.every.nth(i.nextRenewal!, -1))?.millisecondsSinceEpoch,
            'trial': i.isTrial,
            'logo': logoUrl(i.merchant, 96),
            'charge': i.baseAmount == null ? '?' : money(i.baseAmount!, base),
          })
      .toList();
  try {
    await HomeWidget.saveWidgetData('trials', jsonEncode(due));
    await HomeWidget.updateWidget(androidName: 'TrialWidgetProvider', iOSName: 'TrialWidget');
  } catch (_) {
    // Widget extension not installed (e.g. iOS target not yet added in Xcode).
  }
}
