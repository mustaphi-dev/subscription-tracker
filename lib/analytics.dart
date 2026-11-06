import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'data.dart';
import 'home.dart';
import 'ui.dart';

const _typeColors = {
  'subscription': Color(0xFF3D7BFF),
  'free_trial': kAccent,
  'installment': kAmber,
};
const _typeNames = {'subscription': 'Subscriptions', 'free_trial': 'Trials (after conversion)', 'installment': 'Pay later'};

class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final items = (ref.watch(itemsProvider).value ?? []).where((i) => i.status == 'active' || i.status == 'pending_confirmation').toList();
    final sources = ref.watch(sourcesProvider).value ?? [];
    final outgoing = items.where((i) => i.type != 'income').toList();
    final monthlyOut = outgoing.fold(0.0, (s, i) => s + i.monthlyBase);
    final monthlyIn = items.where((i) => i.type == 'income').fold(0.0, (s, i) => s + i.monthlyBase);

    return TabPage(
      title: 'Insights',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Insights', style: display(34)),
              const SizedBox(height: 16),
              const Text('Recurring outgoings per month', style: label),
              const SizedBox(height: 4),
              BigMoney(monthlyOut, base, size: 40),
              if (monthlyIn > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${(monthlyOut / monthlyIn * 100).clamp(0, 999).toStringAsFixed(0)}% of your ${money(monthlyIn, base)} monthly income',
                  style: const TextStyle(color: kMuted, fontSize: 13, fontFeatures: tabular),
                ),
              ],
            ]),
          ),
        ),
        if (outgoing.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Surface(
                padding: EdgeInsets.all(24),
                child: Text('Add a subscription, trial or installment and your charts appear here.',
                    textAlign: TextAlign.center, style: TextStyle(color: kMuted, height: 1.4)),
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(child: _ProjectedSpend(outgoing, base)),
          SliverToBoxAdapter(
            child: sources.isEmpty ? const _RunwayPlaceholder() : _Runway(items: items, sources: sources, base: base),
          ),
          SliverToBoxAdapter(child: _Breakdown(outgoing, sources, base)),
          SliverToBoxAdapter(child: _TopMerchants(outgoing, base)),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Surface(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: caption)],
            const SizedBox(height: 18),
            child,
          ]),
        ),
      );
}

// ───────── 6-month projected spend ─────────

class _ProjectedSpend extends StatelessWidget {
  const _ProjectedSpend(this.items, this.base);
  final List<FinancialItem> items;
  final String base;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(6, (k) => DateTime(now.year, now.month + k, 1));
    final charges = chargesBetween(items, months.first, DateTime(now.year, now.month + 6, 1));
    final totals = [
      for (final m in months)
        charges.where((c) => c.date.year == m.year && c.date.month == m.month).fold(0.0, (s, c) => s - c.amount),
    ];
    final maxY = max(totals.reduce(max), 1.0) * 1.2;

    return _Card(
      title: 'Projected spend',
      subtitle: 'Next 6 months, including trials that convert',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => const FlLine(color: kLine, strokeWidth: 1, dashArray: [3, 4]),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: maxY / 4,
                  getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox() : Text(compactMoney(v, base), style: caption),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(DateFormat('MMM').format(months[v.toInt()]), style: caption),
                  ),
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchCallback: (e, r) {
                if (e is FlTapDownEvent) HapticFeedback.selectionClick();
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => kSurfaceHi,
                tooltipBorderRadius: BorderRadius.circular(10),
                getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                  money(rod.toY, base),
                  const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular),
                ),
              ),
            ),
            barGroups: [
              for (var k = 0; k < 6; k++)
                BarChartGroupData(x: k, barRods: [
                  BarChartRodData(
                    toY: totals[k],
                    width: 26,
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: k == 0 ? [kAccent.withValues(alpha: 0.6), kAccent] : [kSurfaceHi, const Color(0xFF2A2E39)],
                    ),
                  ),
                ]),
            ],
          ),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

// ───────── 30-day balance runway ─────────

class _Runway extends StatelessWidget {
  const _Runway({required this.items, required this.sources, required this.base});
  final List<FinancialItem> items;
  final List<PaymentSource> sources;
  final String base;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final charges = chargesBetween(items, today, today.add(const Duration(days: 31)));
    var bal = sources.fold(0.0, (s, a) => s + (a.baseBalance ?? 0));
    final spots = <FlSpot>[FlSpot(0, bal)];
    var low = (day: 0, value: bal);
    for (var d = 0; d <= 30; d++) {
      bal += charges.where((c) => c.date.difference(today).inDays == d).fold(0.0, (s, c) => s + c.amount);
      spots.add(FlSpot(d.toDouble(), bal));
      if (bal < low.value) low = (day: d, value: bal);
    }
    final ys = spots.map((s) => s.y);
    final minY = min(ys.reduce(min), 0.0), maxY = ys.reduce(max);
    final pad = max((maxY - minY) * 0.15, 10.0);
    final goesNegative = low.value < 0;
    final lineColor = goesNegative ? kCrimson : kMint;

    return _Card(
      title: 'Balance runway',
      subtitle: goesNegative
          ? 'Dips to ${money(low.value, base)} on ${DateFormat('d MMM').format(today.add(Duration(days: low.day)))} — top up before then'
          : 'Lowest point ${money(low.value, base)} on ${DateFormat('d MMM').format(today.add(Duration(days: low.day)))}',
      child: SizedBox(
        height: 170,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 30,
            minY: minY - pad,
            maxY: maxY + pad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 10,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(v == 0 ? 'Today' : DateFormat('d MMM').format(today.add(Duration(days: v.toInt()))), style: caption),
                  ),
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              if (minY - pad < 0) HorizontalLine(y: 0, color: kCrimson.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [4, 4]),
            ]),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => kSurfaceHi,
                tooltipBorderRadius: BorderRadius.circular(10),
                getTooltipItems: (ss) => [
                  for (final s in ss)
                    LineTooltipItem(
                      '${DateFormat('d MMM').format(today.add(Duration(days: s.x.toInt())))}\n',
                      caption,
                      children: [TextSpan(text: money(s.y, base), style: const TextStyle(fontWeight: FontWeight.w700, color: kText, fontFeatures: tabular))],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isStepLineChart: true,
                color: lineColor,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [lineColor.withValues(alpha: 0.28), lineColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunwayPlaceholder extends ConsumerWidget {
  const _RunwayPlaceholder();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Card(
        title: 'Balance runway',
        subtitle: 'See when renewals would run an account dry',
        child: Row(children: [
          const Expanded(child: Text('Connect an account to project your balance over the next 30 days.', style: TextStyle(color: kMuted, height: 1.4))),
          const SizedBox(width: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => ref.read(tabProvider.notifier).set(2),
            child: const Text('Connect'),
          ),
        ]),
      );
}

// ───────── Donut breakdown ─────────

class _Breakdown extends StatefulWidget {
  const _Breakdown(this.items, this.sources, this.base);
  final List<FinancialItem> items;
  final List<PaymentSource> sources;
  final String base;
  @override
  State<_Breakdown> createState() => _BreakdownState();
}

class _BreakdownState extends State<_Breakdown> {
  int _byAccount = 0;
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final accounts = {for (final s in widget.sources) s.id: s};
    final byAccount = _byAccount == 1;
    final groups = <String, double>{};
    for (final i in widget.items) {
      final k = byAccount ? (accounts.containsKey(i.sourceId) ? i.sourceId! : 'none') : i.type;
      groups[k] = (groups[k] ?? 0) + i.monthlyBase;
    }
    final entries = groups.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);
    Color colorOf(String k) => (byAccount ? accounts[k]?.color : _typeColors[k]) ?? kFaint;
    String nameOf(String k) => (byAccount ? accounts[k]?.bank : _typeNames[k]) ?? 'Not assigned';
    final focus = _touched != null && _touched! < entries.length ? entries[_touched!] : null;

    return _Card(
      title: 'Where it goes',
      subtitle: 'Monthly equivalent',
      child: Column(children: [
        Segmented(labels: const ['By type', 'By account'], selected: _byAccount, onSelect: (i) => setState(() {
              _byAccount = i;
              _touched = null;
            })),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 62,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(touchCallback: (e, r) {
                  if (!e.isInterestedForInteractions) return;
                  final i = r?.touchedSection?.touchedSectionIndex;
                  if (i != null && i >= 0 && i != _touched) {
                    HapticFeedback.selectionClick();
                    setState(() => _touched = i);
                  }
                }),
                sections: [
                  for (var k = 0; k < entries.length; k++)
                    PieChartSectionData(
                      value: entries[k].value,
                      color: colorOf(entries[k].key),
                      radius: k == _touched ? 30 : 22,
                      showTitle: false,
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 350),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(focus == null ? 'Total' : nameOf(focus.key), style: caption, maxLines: 1),
              Text(money(focus?.value ?? total, widget.base), style: display(20)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        for (var k = 0; k < entries.length; k++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _touched = k),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(entries[k].key), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 10),
                Expanded(child: Text(nameOf(entries[k].key), style: TextStyle(fontWeight: k == _touched ? FontWeight.w700 : FontWeight.w500))),
                Text('${(entries[k].value / total * 100).toStringAsFixed(0)}%', style: caption),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: Text(money(entries[k].value, widget.base), textAlign: TextAlign.right, style: const TextStyle(fontFeatures: tabular)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ───────── Top merchants ─────────

class _TopMerchants extends StatelessWidget {
  const _TopMerchants(this.items, this.base);
  final List<FinancialItem> items;
  final String base;
  @override
  Widget build(BuildContext context) {
    final top = [...items]..sort((a, b) => b.monthlyBase.compareTo(a.monthlyBase));
    final maxV = top.isEmpty ? 1.0 : max(top.first.monthlyBase, 0.01);
    return _Card(
      title: 'Biggest commitments',
      child: Column(children: [
        for (final i in top.take(5)) _MerchantBar(i, maxV, base),
      ]),
    );
  }
}

/// One merchant's monthly cost, with a bar scaled against the biggest.
class _MerchantBar extends StatelessWidget {
  const _MerchantBar(this.i, this.maxV, this.base);
  final FinancialItem i;
  final double maxV;
  final String base;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          MerchantAvatar(i.merchant, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(i.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${money(i.monthlyBase, base)}/mo', style: const TextStyle(fontFeatures: tabular, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: i.monthlyBase / maxV),
                  duration: const Duration(milliseconds: 800),
                  curve: springOut,
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 5, backgroundColor: kSurfaceHi, color: _typeColors[i.type] ?? kAccent),
                ),
              ),
            ]),
          ),
        ]),
      );
}
