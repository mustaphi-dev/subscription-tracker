import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avatars.dart';
import 'brands.dart';
import 'data.dart';
import 'ui.dart';

/// Calendar days from [now] to [when]: 0 today, 1 tomorrow, negative once past. Rounded, so a
/// day that DST makes 23 or 25 hours long still counts as one.
int daysUntil(DateTime when, [DateTime? now]) =>
    (DateUtils.dateOnly(when).difference(DateUtils.dateOnly(now ?? DateTime.now())).inHours / 24).round();

String relativeDue(DateTime? due) {
  if (due == null) return 'No date';
  return switch (daysUntil(due)) {
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
  final days = daysUntil(when, now);
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

/// [i]'s details, open, in a bottom sheet.
Future<void> showItemSheet(BuildContext context, FinancialItem i) =>
    showSheet(context, Padding(padding: const EdgeInsets.only(bottom: 8), child: ItemRow(i, pinned: true)));

/// Where "cancel" goes for [i]: the merchant's page, the bank's app, or a web search; with the button's label.
(String label, String url) cancelTarget(FinancialItem i, PaymentSource? s) {
  if (i.cancelUrl case final url?) return ('Cancel at merchant', url);
  if (bankAppUrl(s) case final url?) return ('Open bank app', url);
  return ('How to cancel', 'https://www.google.com/search?q=cancel+${Uri.encodeComponent(i.merchant)}');
}

/// Saves [status] for [i]; false, after telling the user, if it didn't save.
Future<bool> _setStatus(BuildContext context, FinancialItem i, String status) async {
  try {
    await setItemStatus(i.id, status);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t update ${i.merchant}. Try again.', e);
    return false;
  }
}

/// Flat row for grouped lists. Tap to unfold details (or open them in a sheet); swipe left to cancel.
class ItemRow extends ConsumerStatefulWidget {
  const ItemRow(this.item, {super.key, this.sheet = false, this.pinned = false});
  final FinancialItem item;

  /// Tap opens the details in a bottom sheet instead of unfolding in the list.
  final bool sheet;

  /// Details stay open and the row can't be swiped: the row as shown inside that sheet.
  final bool pinned;
  @override
  ConsumerState<ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<ItemRow> {
  late bool _open = widget.pinned;

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final base = ref.watch(baseProvider);
    final source = (ref.watch(sourcesProvider).value ?? []).where((s) => s.id == i.sourceId).firstOrNull;
    final income = i.type == 'income';
    final pending = i.status == 'pending_confirmation';

    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.pinned
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.sheet ? showItemSheet(context, i) : setState(() => _open = !_open);
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
                '${relativeDue(i.dueAt)} · ${i.every.label}',
                style: TextStyle(fontSize: 13, color: i.dueSoon ? kCrimson : kMuted),
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
        if (!await confirmCancel(context, i) || !context.mounted || !await _setStatus(context, i, 'cancelled')) return false;
        if (context.mounted) {
          showToast(context, '${i.merchant} marked as cancelled',
              closeSheets: false, onUndo: () => _setStatus(context, i, i.status)); // row is still animating out
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

  /// [k] on the left, [v] (text, or a widget such as a live countdown) on the right.
  Widget _kv(String k, Object v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(k, style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(width: 16),
          // Expanded (not Spacer + Flexible, which split the row and started values mid-way).
          Expanded(
            child: v is Widget
                ? Align(alignment: Alignment.centerRight, child: v)
                : Text('$v', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontFeatures: tabular)),
          ),
        ]),
      );

  Widget _installment(FinancialItem i) {
    final total = i.installTotal ?? 0;
    final last = i.finalPayment;
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

  Widget _trial(FinancialItem i, String base, PaymentSource? s) {
    final (cancelLabel, cancelUrl) = cancelTarget(i, s);
    final confirm = i.status == 'pending_confirmation';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (i.trialEnd != null) _kv('Converts in', LiveCountdown(i.trialEnd!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      _kv('Charged after trial', i.postTrialAmount == null ? 'Unknown' : dualMoney(i.postTrialAmount!, i.currency, i.baseAmount, base)),
      _kv('Paid from', s == null ? 'Not assigned' : '${s.bank} · ${s.name}'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => launchUrl(Uri.parse(cancelUrl), mode: LaunchMode.externalApplication),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              if (!confirm && !await confirmCancel(context, i)) return;
              if (!mounted || !await _setStatus(context, i, confirm ? 'active' : 'cancelled')) return;
              if (mounted) {
                showToast(context, confirm ? 'Got it. We\'ll remind you before it starts charging.' : 'Trial cancelled. No more reminders.',
                    onUndo: confirm ? null : () => _setStatus(context, i, i.status));
              }
            },
            child: Text(confirm ? 'Confirm trial' : 'Mark cancelled'),
          ),
        ),
      ]),
    ]);
  }

  Widget _recurring(FinancialItem i, PaymentSource? s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _kv('Type', itemTypes[i.type]?.name ?? i.type),
        _kv('Frequency', i.every.label),
        if (i.type != 'income') _kv('Total spent so far', money(i.totalSpent, i.currency)),
        _kv(i.type == 'income' ? 'Paid into' : 'Paid from', s == null ? 'Not assigned' : '${s.bank} · ${s.name}'),
        _kv('Source', switch (i.detectedVia) { 'open_banking' => 'Your bank', 'email_ai' => 'Receipt scan', _ => 'Added by you' }),
      ]);
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

// ───────── Confirm detected trial (push deep-link) ─────────

/// The route of [ConfirmTrialScreen]; the router declares it as `confirmPath(':id')`.
String confirmPath(String id) => '/confirm/$id';

class ConfirmTrialScreen extends ConsumerWidget {
  const ConfirmTrialScreen(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = (ref.watch(itemsProvider).value ?? []).where((i) => i.id == id).firstOrNull;
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => context.go('/')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text('Is this a free trial?', style: display(28)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text(
                  'We spotted a card check from this merchant. Confirm it so we can warn you before it starts charging.',
                  style: TextStyle(color: kMuted, height: 1.4),
                ),
              ),
              if (item == null) const Center(child: CircularProgressIndicator()) else ItemGroup([item], flat: true),
            ],
          ),
        ),
      ),
    );
  }
}
