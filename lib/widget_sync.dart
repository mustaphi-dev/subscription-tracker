import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'data.dart';
import 'ui.dart';

Future<void> updateTrialWidget(List<FinancialItem> items, String base) async {
  final trials = (items.where((i) => i.isLive && i.isRunningTrial).toList()..sort((a, b) => a.trialEnd!.compareTo(b.trialEnd!)))
      .take(3)
      .map((t) => {
            'name': t.merchant,
            'ends_at': t.trialEnd!.millisecondsSinceEpoch,
            'charge': t.baseAmount == null ? '?' : money(t.baseAmount!, base),
          })
      .toList();
  try {
    await HomeWidget.saveWidgetData('trials', jsonEncode(trials));
    await HomeWidget.updateWidget(androidName: 'TrialWidgetProvider', iOSName: 'TrialWidget');
  } catch (_) {
    // Widget extension not installed (e.g. iOS target not yet added in Xcode).
  }
}
