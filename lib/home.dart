import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'accounts.dart' show refreshBanks;
import 'add.dart';
import 'avatars.dart';
import 'brands.dart';
import 'data.dart';
import 'item_tile.dart';
import 'tab_page.dart';
import 'ui.dart';
import 'upcoming.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseProvider);
    final all = ref.watch(itemsProvider).value ?? [];
    final sources = ref.watch(sourcesProvider).value ?? [];
    final live = ref.watch(liveItemsProvider);
    final out = live.monthlyOut, income = live.monthlyIn;
    final trials = live.where((i) => i.isRunningTrial).toList();

    return TabPage(
      title: 'Home',
      onRefresh: () => refreshBanks(context, ref),
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            label: sources.isEmpty ? 'Monthly outgoings' : 'Total balance',
            value: sources.isEmpty ? out : sources.totalBase,
            base: base,
            income: income,
            out: out,
          ),
        ),
        if (all.isNotEmpty) const SliverToBoxAdapter(child: _NextDays()),
        if (trials.isNotEmpty) SliverToBoxAdapter(child: _TrialRings(trials)),
        if (all.isEmpty) const SliverToBoxAdapter(child: _EmptyState()) else ...upcomingSlivers(context, ref, ref.watch(filteredItemsProvider), limit: 6),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.label, required this.value, required this.base, required this.income, required this.out});
  final String label, base;
  final double value, income, out;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: label_),
          const SizedBox(height: 6),
          BigMoney(value, base, size: 52),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pill(icon: CupertinoIcons.arrow_down_left, color: kMint, text: '${compactMoney(income, base)} in / mo'),
            _Pill(icon: CupertinoIcons.arrow_up_right, color: kCrimson, text: '${compactMoney(out, base)} out / mo'),
          ]),
        ]),
      );
  static const label_ = TextStyle(color: kMuted, fontSize: 14, fontWeight: FontWeight.w500);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ]),
      );
}

/// 14-day strip: each day shows its charges as provider-coloured dots and the day total.
class _NextDays extends ConsumerWidget {
  const _NextDays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseProvider);
    final sources = {for (final s in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) s.id: s.color};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final charges = chargesBetween(ref.watch(liveItemsProvider), today, today.add(const Duration(days: 14)));
    final total = charges.spend;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Next 14 days', trailing: Text('${money(total, base)} out', style: const TextStyle(color: kMuted, fontSize: 13, fontFeatures: tabular))),
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 14,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, k) {
            final day = today.add(Duration(days: k));
            final onDay = charges.where((c) => DateUtils.isSameDay(c.date, day)).toList();
            final spend = onDay.spend;
            final isToday = k == 0;
            return Pressable(
              onTap: () {
                if (onDay.isEmpty) return;
                showSheet(context, DaySheet(day: day, items: onDay.map((c) => c.item).toList()));
              },
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? kText : kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isToday ? kText : kLine),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(DateFormat('E').format(day).substring(0, 2), style: TextStyle(fontSize: 11, color: isToday ? kBg.withValues(alpha: 0.6) : kMuted)),
                  Text('${day.day}', style: display(18, color: isToday ? kBg : kText)),
                  // One compact slot: the day's spend if any, otherwise dots for income/other items.
                  SizedBox(
                    height: 13,
                    child: spend > 0
                        ? Text(compactMoney(spend, base),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isToday ? kBg : kMuted, fontFeatures: tabular))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (final c in onDay.take(4))
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.amount > 0 ? kMint : (sources[c.item.sourceId] ?? kAccent),
                                ),
                              ),
                          ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class DaySheet extends StatelessWidget {
  const DaySheet({super.key, required this.day, required this.items});
  final DateTime day;
  final List<FinancialItem> items;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(DateFormat('EEEE d MMMM').format(day), style: display(22)),
        ),
        Flexible(child: SingleChildScrollView(child: ItemGroup(items, flat: true))),
        const SizedBox(height: 16),
      ]);
}

class _TrialRings extends StatelessWidget {
  const _TrialRings(this.trials);
  final List<FinancialItem> trials;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('Free trials ending'),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: trials.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final t = trials[i];
              final left = t.trialEnd!.difference(DateTime.now());
              final urgent = left.inHours < 48;
              final tone = urgent ? kCrimson : kAccent;
              final known = t.postTrialAmount != null;
              return Surface(
                onTap: () => showItemSheet(context, t),
                padding: const EdgeInsets.all(16),
                border: urgent ? kCrimson.withValues(alpha: 0.35) : null,
                child: SizedBox(
                  width: 168,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Ring(progress: t.trialProgress, color: tone, center: MerchantAvatar(t.merchant, size: 30)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(99)),
                        child: Text('Ends ${DateFormat('d MMM').format(t.trialEnd!)}', style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const Spacer(),
                    Text(t.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
                    Text(dueLabel(t.trialEnd!), style: display(20, color: urgent ? kCrimson : kText)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: (known ? tone : kMuted).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        known ? 'Then ${priceTag(t.postTrialAmount!, t.currency, t.cycle)}' : 'Charge unknown',
                        style: TextStyle(color: known ? tone : kMuted, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]);
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.color, required this.center});
  final double progress;
  final Color color;
  final Widget center;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 1100),
        curve: springOut,
        builder: (_, v, child) => CustomPaint(painter: _RingPainter(v, color), child: child),
        child: SizedBox.square(dimension: 52, child: Center(child: center)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color);
  final double v;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r.deflate(3), 0, 2 * pi, false, p..color = kLine);
    canvas.drawArc(r.deflate(3), -pi / 2, 2 * pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
        child: Surface(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            SizedBox(
              height: 92,
              child: Stack(alignment: Alignment.center, children: [
                for (final (dx, a, c) in [(-34.0, -0.18, kAccent), (34.0, 0.18, kMint), (0.0, 0.0, kBlue)])
                  Transform.translate(
                    offset: Offset(dx, dx == 0 ? -6 : 6),
                    child: Transform.rotate(
                      angle: a,
                      child: Container(
                        width: 58,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, kBg, 0.6)!]),
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Track every renewal', style: display(22)),
            const SizedBox(height: 8),
            const Text(
              'Scan a receipt, log a subscription, or connect an account. We\'ll warn you before trials convert and when a balance runs short.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => scanReceipt(context), child: const Text('Scan a receipt')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => showSheet(context, const ManualItemForm()), child: const Text('Add manually')),
          ]),
        ),
      ).fadeRise(ms: 400, rise: 0.05);
}
