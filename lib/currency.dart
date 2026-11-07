import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'countries.dart';
import 'ui.dart';

const currencyNames = {
  'GBP': 'British pound', 'USD': 'US dollar', 'EUR': 'Euro', 'GHS': 'Ghanaian cedi', 'NGN': 'Nigerian naira',
  'KES': 'Kenyan shilling', 'ZAR': 'South African rand', 'CAD': 'Canadian dollar', 'AUD': 'Australian dollar',
  'CHF': 'Swiss franc', 'JPY': 'Japanese yen', 'INR': 'Indian rupee', 'AED': 'UAE dirham',
};

// ───────── Currency picker ─────────

const currencies = [
  ('GBP', '🇬🇧', 'British pound'),
  ('USD', '🇺🇸', 'US dollar'),
  ('EUR', '🇪🇺', 'Euro'),
  ('GHS', '🇬🇭', 'Ghanaian cedi'),
];

/// The picker's currencies, plus the user's own if it isn't one of them (e.g. NGN after picking Nigeria).
List<(String, String, String)> currencyChoices(String current) {
  if (currencies.any((c) => c.$1 == current)) return currencies;
  final home = countries.where((c) => c.currency == current).firstOrNull;
  return [...currencies, (current, home?.flag ?? '💱', currencyNames[current] ?? home?.name ?? current)];
}

/// Custom popover that springs out of its top-right corner, just under the top bar.
/// Opens with a spring; closes fast (showGeneralDialog can't have a shorter reverse duration).
Future<String?> pickCurrency(BuildContext context, String current) => Navigator.of(context, rootNavigator: true).push<String>(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 52, right: 12),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 248,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kSurfaceHi,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kLine),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 12))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Text('DISPLAY CURRENCY', style: TextStyle(color: kFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ),
                for (final (code, flag, name) in currencyChoices(current))
                  Pressable(
                    scale: 0.98,
                    onTap: () => Navigator.pop(ctx, code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: code == current ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        Text(flag, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(code, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(name, style: caption),
                          ]),
                        ),
                        AnimatedOpacity(
                          opacity: code == current ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(CupertinoIcons.checkmark, color: kMint, size: 20),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: const Interval(0, 0.5), reverseCurve: Curves.easeIn),
        child: ScaleTransition(
          alignment: Alignment.topRight,
          scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: springBounce, reverseCurve: Curves.easeIn)),
          child: child,
        ),
      ),
    ));

class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final flag = currencyChoices(current).where((c) => c.$1 == current).firstOrNull?.$2 ?? '💱';
    return Semantics(
      button: true,
      label: 'Display currency $current',
      child: Pressable(
        onTap: () async {
          final picked = await pickCurrency(context, current);
          if (picked != null && picked != current) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(current, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 2),
            const Icon(CupertinoIcons.chevron_up_chevron_down, size: 16, color: kMuted),
          ]),
        ),
      ),
    );
  }
}
