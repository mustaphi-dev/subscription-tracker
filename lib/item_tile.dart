import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brands.dart';
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

/// Rounded, calendar-based label for glanceable cards: Today, Tomorrow, In 5 days, In 2 weeks, In 3 months.
String dueLabel(DateTime when, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final days = DateUtils.dateOnly(when).difference(DateUtils.dateOnly(n)).inDays;
  if (days < 0) return 'Ended';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 14) return 'In $days days';
  if (days < 60) return 'In ${(days / 7).round()} weeks';
  return 'In ${(days / 30).round()} months';
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

/// Flat row for grouped lists. Tap to unfold details (or open them in a sheet); swipe left to cancel.
class ItemRow extends ConsumerStatefulWidget {
  const ItemRow(this.item, {super.key, this.initiallyOpen = false, this.sheet = false, this.pinned = false});
  final FinancialItem item;
  final bool initiallyOpen;

  /// Tap opens the details in a bottom sheet instead of unfolding in the list.
  final bool sheet;

  /// Details stay open and the row can't be swiped: the row as shown inside that sheet.
  final bool pinned;
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
      onTap: widget.pinned
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.sheet
                  ? showSheet(context, Padding(padding: const EdgeInsets.only(bottom: 8), child: ItemRow(i, initiallyOpen: true, pinned: true)))
                  : setState(() => _open = !_open);
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
      direction: income || widget.pinned ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: kCrimson.withValues(alpha: 0.12),
        child: const Text('Cancel', style: TextStyle(color: kCrimson, fontWeight: FontWeight.w600)),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        final ok = await confirmCancel(context, i);
        if (ok != true) return false;
        await setItemStatus(i.id, 'cancelled');
        if (context.mounted) {
          showToast(context, '${i.merchant} marked as cancelled',
              closeSheets: false, onUndo: () => setItemStatus(i.id, i.status)); // row is still animating out
        }
        return true;
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 420),
        curve: springOut,
        alignment: Alignment.topCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          Expanded(child: OutlinedButton(onPressed: () => _openCancel(i, s), child: Text(i.cancelUrl != null ? 'Cancel at merchant' : bankAppUrl(s) != null ? 'Open bank app' : 'How to cancel'))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: () async {
                HapticFeedback.mediumImpact();
                final confirm = i.status == 'pending_confirmation';
                if (!confirm && !await confirmCancel(context, i)) return;
                await setItemStatus(i.id, confirm ? 'active' : 'cancelled');
                if (mounted) {
                  showToast(context, confirm ? 'Got it. We\'ll remind you before it starts charging.' : 'Trial cancelled. No more reminders.',
                      onUndo: confirm ? null : () => setItemStatus(i.id, i.status));
                }
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
        _kv('Source', switch (i.detectedVia) { 'open_banking' => 'Your bank', 'email_ai' => 'Receipt scan', _ => 'Added by you' }),
      ]);

  Future<void> _openCancel(FinancialItem i, PaymentSource? s) async {
    final url = i.cancelUrl ?? bankAppUrl(s) ?? 'https://www.google.com/search?q=cancel+${Uri.encodeComponent(i.merchant)}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// The bank's site for [s]; iOS hands it to the bank's app when that app claims the link.
String? bankAppUrl(PaymentSource? s) {
  if (s == null) return null;
  final who = '${s.provider} ${s.institution ?? ''}';
  const deep = {'revolut.com': 'https://revolut.com/app', 'wise.com': 'https://wise.com/account', 'lloydsbank.com': 'https://www.lloydsbank.com/app.html', 'paypal.com': 'https://www.paypal.com/myaccount/autopay'};
  final domain = logoQuery(who)?.domain;
  return domain == null ? null : deep[domain] ?? 'https://www.$domain';
}

/// Branded "are you sure" sheet. Marking cancelled only stops tracking, so the copy says so plainly.
Future<bool> confirmCancel(BuildContext context, FinancialItem i) async {
  final charge = i.isTrial
      ? (i.postTrialAmount == null ? null : priceTag(i.postTrialAmount!, i.currency, i.cycle))
      : priceTag(i.amount, i.currency, i.cycle);
  return confirmSheet(
    context,
    leading: MerchantAvatar(i.merchant, size: 56),
    title: 'Cancel ${i.merchant}?',
    body: 'We\'ll stop tracking it and turn off its reminders. '
        'This doesn\'t cancel it with ${i.merchant}${charge == null ? '.' : ', so make sure you have, or you\'ll still pay $charge.'}',
    action: 'Mark as cancelled',
  );
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
  const ItemGroup(this.items, {super.key, this.flat = false, this.sheet = false});
  final List<FinancialItem> items;

  /// Rows open their details in a bottom sheet (see [ItemRow.sheet]).
  final bool sheet;

  /// Sheets list rows straight on the sheet, separated by lines; pages wrap them in a card.
  final bool flat;
  @override
  Widget build(BuildContext context) {
    final rows = Column(children: [
      for (var k = 0; k < items.length; k++) ...[
        if (k > 0) const Divider(height: 1, indent: 70, color: kLine),
        ItemRow(items[k], sheet: sheet),
      ],
    ]);
    if (flat) return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: rows);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Surface(padding: EdgeInsets.zero, child: rows),
      ),
    );
  }
}
