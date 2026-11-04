import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'ui.dart';

String relativeDue(DateTime? due) {
  if (due == null) return 'No date';
  final today = DateTime.now();
  final days = DateTime(due.year, due.month, due.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  return switch (days) {
    < 0 => 'Overdue',
    0 => 'Today',
    1 => 'Tomorrow',
    < 7 => DateFormat('EEEE').format(due),
    _ => DateFormat('d MMM').format(due),
  };
}

String countdown(Duration d) {
  if (d.isNegative) return 'Ended';
  final h = d.inHours % 24, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return d.inDays > 0 ? '${d.inDays}d ${two(h)}h ${two(m)}m' : '${two(h)}:${two(m)}:${two(s)}';
}

class LiveCountdown extends ConsumerWidget {
  const LiveCountdown(this.until, {super.key, this.style});
  final DateTime until;
  final TextStyle? style;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Text(countdown(until.difference(now)), style: (style ?? const TextStyle()).copyWith(fontFeatures: tabular));
  }
}

const _cycleLabel = {'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly', 'once': 'One-off'};
const _typeLabel = {'free_trial': 'Free trial', 'subscription': 'Subscription', 'installment': 'Installment', 'income': 'Income'};

/// Flat row for grouped lists. Tap to unfold details; swipe left to cancel.
class ItemRow extends ConsumerStatefulWidget {
  const ItemRow(this.item, {super.key, this.initiallyOpen = false});
  final FinancialItem item;
  final bool initiallyOpen;
  @override
  ConsumerState<ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<ItemRow> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final source = (ref.watch(sourcesProvider).value ?? []).where((s) => s.id == i.sourceId).firstOrNull;
    final income = i.type == 'income';
    final pending = i.status == 'pending_confirmation';
    final soon = i.dueAt != null && i.dueAt!.difference(DateTime.now()).inHours < 24;

    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _open = !_open);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          MerchantAvatar(i.merchant, dot: source?.color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(i.merchant,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (i.isTrial) ...[const SizedBox(width: 6), _Tag(pending ? 'Confirm?' : 'Trial', pending ? kAmber : kAccent)],
              ]),
              const SizedBox(height: 3),
              Text(
                '${relativeDue(i.dueAt)} · ${_cycleLabel[i.cycle]}',
                style: TextStyle(fontSize: 13, color: soon ? kCrimson : kMuted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${income ? '+' : '−'}${money(i.chargeAmount, i.currency)}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFeatures: tabular, color: income ? kMint : kText),
            ),
            if (i.currency != base && i.baseAmount != null)
              Text('≈ ${money(i.baseAmount!, base)}', style: const TextStyle(color: kMuted, fontSize: 12, fontFeatures: tabular)),
          ]),
        ]),
      ),
    );

    return Dismissible(
      key: ValueKey(i.id),
      direction: income ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: kCrimson.withValues(alpha: 0.12),
        child: const Text('Cancel', style: TextStyle(color: kCrimson, fontWeight: FontWeight.w600)),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        await setItemStatus(i.id, 'cancelled');
        if (context.mounted) showToast(context, '${i.merchant} marked as cancelled', closeSheets: false); // row is still animating out
        return true;
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 420),
        curve: springOut,
        alignment: Alignment.topCenter,
        child: Column(children: [
          row,
          if (_open)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(16)),
              child: switch (i.type) {
                'installment' => _installment(i),
                'free_trial' => _trial(i, base, source),
                _ => _recurring(i, source),
              },
            ),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(k, style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(width: 16),
          // Expanded (not Spacer + Flexible, which split the row and started values mid-way).
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontFeatures: tabular))),
        ]),
      );

  Widget _installment(FinancialItem i) {
    final total = i.installTotal ?? 0;
    final last = i.nextRenewal == null || total == 0
        ? null
        : DateTime(i.nextRenewal!.year, i.nextRenewal!.month + (total - i.installPaid - 1), i.nextRenewal!.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
        children: List.generate(
          total,
          (k) => Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: k < i.installPaid ? 1 : 0),
              duration: Duration(milliseconds: 400 + k * 120),
              curve: springOut,
              builder: (_, v, _) => Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Color.lerp(kLine, kMint, v),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _kv('Progress', 'Payment ${i.installPaid + 1} of $total'),
      if (i.installRemaining != null) _kv('Remaining payoff', money(i.installRemaining!, i.currency)),
      if (last != null) _kv('Final payment', DateFormat('d MMM y').format(last)),
    ]);
  }

  Widget _trial(FinancialItem i, String base, PaymentSource? s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (i.trialEnd != null) _kvWidget('Converts in', LiveCountdown(i.trialEnd!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        _kv('Charged after trial', i.postTrialAmount == null ? 'Unknown' : dualMoney(i.postTrialAmount!, i.currency, i.baseAmount, base)),
        _kv('Paid from', s == null ? 'Not assigned' : '${s.bank} · ${s.name}'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _openCancel(i, s), child: Text(i.cancelUrl == null ? 'Open bank app' : 'Cancel at merchant'))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: () async {
                HapticFeedback.mediumImpact();
                final confirm = i.status == 'pending_confirmation';
                await setItemStatus(i.id, confirm ? 'active' : 'cancelled');
                if (mounted) showToast(context, confirm ? 'Trial confirmed — we\'ll remind you before it converts' : 'Trial cancelled, alerts silenced');
              },
              child: Text(i.status == 'pending_confirmation' ? 'Confirm trial' : 'Mark cancelled'),
            ),
          ),
        ]),
      ]);

  Widget _kvWidget(String k, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Text(k, style: const TextStyle(color: kMuted, fontSize: 13)), const Spacer(), v]),
      );

  Widget _recurring(FinancialItem i, PaymentSource? s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _kv('Type', _typeLabel[i.type] ?? i.type),
        _kv('Frequency', _cycleLabel[i.cycle] ?? i.cycle),
        if (i.type != 'income') _kv('Total spent so far', money(i.totalSpent, i.currency)),
        _kv(i.type == 'income' ? 'Paid into' : 'Paid from', s == null ? 'Not assigned' : '${s.bank} · ${s.name}'),
        _kv('Added via', switch (i.detectedVia) { 'open_banking' => 'Open Banking', 'email_ai' => 'Receipt scan', _ => 'Manual' }),
      ]);

  Future<void> _openCancel(FinancialItem i, PaymentSource? s) async {
    const bankApps = {
      'revolut': 'https://revolut.com/app',
      'wise': 'https://wise.com/account',
      'lloyds': 'https://www.lloydsbank.com/app.html',
      'paypal': 'https://www.paypal.com/myaccount/autopay',
    };
    final url = i.cancelUrl ?? bankApps[s?.provider] ?? 'https://www.google.com/search?q=cancel+${Uri.encodeComponent(i.merchant)}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// Rows grouped in one solid surface with hairline dividers.
class ItemGroup extends StatelessWidget {
  const ItemGroup(this.items, {super.key, this.color = kSurface});
  final List<FinancialItem> items;

  /// Raise to kSurfaceHi when the group sits on a kSurface sheet.
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Surface(
            color: color,
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var k = 0; k < items.length; k++) ...[
                if (k > 0) const Divider(height: 1, indent: 70, color: kLine),
                ItemRow(items[k]),
              ],
            ]),
          ),
        ),
      );
}
