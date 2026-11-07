import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'data.dart';
import 'item_tile.dart';
import 'tab_page.dart';
import 'ui.dart';

class TrialsCalendarTab extends ConsumerStatefulWidget {
  const TrialsCalendarTab({super.key});
  @override
  ConsumerState<TrialsCalendarTab> createState() => _CalendarState();
}

const _rowH = 52.0, _labelsH = 26.0, _titleH = 108.0; // title = 20 padding + ~44 month + ~30 total, with headroom for larger text settings
const _origin = 1200; // PageView index of the current month; swiping back is bounded at 100 years.

class _CalendarState extends ConsumerState<TrialsCalendarTab> {
  final _pages = PageController(initialPage: _origin);

  /// How far the grid has folded (0 → 1); the day's details only become a sheet as this rises.
  final _fold = ValueNotifier(0.0);
  final _now = DateTime.now();
  late DateTime _month = DateTime(_now.year, _now.month);
  late DateTime _day = DateUtils.dateOnly(_now);

  DateTime _monthAt(int page) => DateTime(_now.year, _now.month + page - _origin);

  @override
  void dispose() {
    _pages.dispose();
    _fold.dispose();
    super.dispose();
  }

  void _onMonth(int page) {
    final m = _monthAt(page);
    final today = DateUtils.dateOnly(DateTime.now());
    HapticFeedback.selectionClick();
    setState(() {
      _month = m;
      _day = DateUtils.isSameMonth(m, today) ? today : m;
    });
  }

  void _goToday() => _pages.animateToPage(_origin, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(baseProvider);
    final items = ref.watch(itemsProvider).value ?? [];
    final today = DateUtils.dateOnly(DateTime.now());
    final monthOut = chargesBetween(items, _month, DateTime(_month.year, _month.month + 1)).spend;
    final onDay = chargesBetween(items, _day, DateTime(_day.year, _day.month, _day.day + 1));
    final trials = items.where((i) => i.isRunningTrial).toList();

    final top = MediaQuery.of(context).padding.top + kTopBarHeight;
    final sel = (_month.weekday - 1 + _day.day - 1) ~/ 7; // grid row holding the selected day

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0) _fold.value = (n.metrics.pixels / (_titleH + 5 * _rowH)).clamp(0.0, 1.0);
        return false;
      },
      child: TabPage(
        title: DateFormat('MMMM').format(_month),
        pad: false,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _Collapsing(
              min: top + _labelsH + _rowH + 8,
              max: top + _titleH + _labelsH + 6 * _rowH + 8,
              builder: (t) => _header(t, top, sel, base, items, monthOut, today),
            ),
          ),
          // The day's details: plain page at rest, turning into a sheet over the calendar as you scroll.
          SliverToBoxAdapter(
            child: ValueListenableBuilder<double>(
              valueListenable: _fold,
              builder: (_, f, _) => Container(
                decoration: BoxDecoration(
                  color: kSurface.withValues(alpha: f),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: kLine.withValues(alpha: kLine.a * f)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.54 * f),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                // Runs to the bottom of the screen (under the nav), and is tall enough for the grid to fold fully.
                constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - (top + _labelsH + _rowH + 8)),
                padding: const EdgeInsets.only(bottom: kNavClearance),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kFaint.withValues(alpha: f),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SectionHeader(
                      DateUtils.isSameDay(_day, today) ? 'Today' : DateFormat('EEEE d MMMM').format(_day),
                      trailing: onDay.isEmpty
                          ? null
                          : Text(
                              money(onDay.spend, base),
                              style: const TextStyle(color: kMuted, fontFeatures: tabular),
                            ),
                    ),
                    onDay.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text('Nothing due on this day.', style: TextStyle(color: kMuted)),
                          )
                        : ItemGroup(onDay.map((c) => c.item).toList(), flat: true),
                    if (trials.isNotEmpty) ...[
                      const SectionHeader('Active trials'),
                      ItemGroup(trials, flat: true),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _step = Duration(milliseconds: 380);
  static final _pill = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: kLine),
  );

  /// Round month arrow, same pill style as the currency picker in the top bar.
  Widget _monthStep(IconData icon, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: Pressable(
      onTap: onTap,
      child: Container(width: 36, height: 36, decoration: _pill, child: Icon(icon, size: 22)),
    ),
  );

  /// [t] is 0 fully open, 1 folded down to the selected week.
  Widget _header(double t, double top, int sel, String base, List<FinancialItem> items, double monthOut, DateTime today) {
    final isCurrent = DateUtils.isSameMonth(_month, today);
    return Column(
      children: [
        SizedBox(height: top), // under the TopBar, which blurs this strip itself
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Content scrolls under the folded header: solid background that fades at the bottom edge,
              // continuous with the top bar's scrim above it.
              if (t > 0)
                Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.8, 1],
                        colors: [kBg, kBg, kBg.withAlpha(0)],
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  ClipRect(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      heightFactor: 1 - t,
                      child: Opacity(
                        opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                        child: SizedBox(
                          height: _titleH,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(DateFormat(_month.year == today.year ? 'MMMM' : 'MMMM y').format(_month), style: display(34)),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          BigMoney(monthOut, base, size: 20, color: kMuted),
                                          const Text('  due', style: TextStyle(color: kMuted)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IgnorePointer(
                                  ignoring: isCurrent,
                                  child: AnimatedOpacity(
                                    opacity: isCurrent ? 0 : 1,
                                    duration: const Duration(milliseconds: 200),
                                    child: Pressable(
                                      onTap: _goToday,
                                      child: Container(
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        alignment: Alignment.center,
                                        decoration: _pill,
                                        child: const Text('Today', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _monthStep(
                                  CupertinoIcons.chevron_left,
                                  'Previous month',
                                  () => _pages.previousPage(duration: _step, curve: Curves.easeOutCubic),
                                ),
                                const SizedBox(width: 6),
                                _monthStep(CupertinoIcons.chevron_right, 'Next month', () => _pages.nextPage(duration: _step, curve: Curves.easeOutCubic)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _labelsH,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                            Expanded(
                              child: Center(
                                child: Text(
                                  d,
                                  style: const TextStyle(color: kFaint, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 6 * _rowH,
                        maxHeight: 6 * _rowH,
                        child: Transform.translate(
                          offset: Offset(0, -t * sel * _rowH),
                          child: PageView.builder(
                            controller: _pages,
                            // ponytail: folded = no month swipe; scroll back up to change month. Week paging if wanted.
                            physics: t > 0.02 ? const NeverScrollableScrollPhysics() : null,
                            onPageChanged: _onMonth,
                            itemBuilder: (_, p) => _monthGrid(_monthAt(p), items, base, today, t, sel),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Always 6 rows (Monday-first), padded with faded days from the neighbouring months.
  Widget _monthGrid(DateTime month, List<FinancialItem> items, String base, DateTime today, double t, int sel) {
    final start = DateTime(month.year, month.month, 2 - month.weekday);
    final out = <int, double>{}, inc = <int, double>{};
    for (final c in chargesBetween(items, start, DateTime(start.year, start.month, start.day + 42))) {
      final k = (DateUtils.dateOnly(c.date).difference(start).inHours + 12) ~/ 24; // DST-safe day index
      if (c.amount < 0) {
        out[k] = (out[k] ?? 0) - c.amount;
      } else {
        inc[k] = (inc[k] ?? 0) + c.amount;
      }
    }
    final peak = out.values.fold(0.0, (m, v) => v > m ? v : m);
    final current = DateUtils.isSameMonth(month, _month);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var r = 0; r < 6; r++)
            Opacity(
              opacity: r == sel || !current ? 1 : (1 - t * 1.5).clamp(0.0, 1.0),
              child: SizedBox(
                height: _rowH,
                child: Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: Builder(
                          builder: (_) {
                            final k = r * 7 + c;
                            final date = DateTime(start.year, start.month, start.day + k);
                            return _cell(date, date.month == month.month, out[k] ?? 0, inc[k] ?? 0, peak, base, today);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(DateTime date, bool inMonth, double spend, double income, double peak, String base, DateTime today) {
    final selected = inMonth && DateUtils.isSameDay(date, _day);
    final isToday = inMonth && DateUtils.isSameDay(date, today);
    final ink = selected
        ? kBg
        : !inMonth
        ? kFaint.withValues(alpha: 0.4)
        : date.isBefore(today)
        ? kFaint
        : kText;
    TextStyle sub(Color c) => TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFeatures: tabular, color: selected ? kBg : c);
    final amount = !inMonth
        ? null
        : spend > 0
        // Brighter = bigger day, so expensive days stand out without tapping.
        ? Text(compactMoney(spend, base), style: sub(kText.withValues(alpha: 0.35 + 0.65 * spend / peak)))
        : income > 0
        ? Text('+${compactMoney(income, base)}', style: sub(kMint))
        : null;

    final cell = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: selected ? kText : Colors.transparent, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: display(16, color: ink, weight: FontWeight.w600),
          ),
          SizedBox(height: 13, child: amount == null ? null : Center(child: amount)),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? (selected ? kBg : kText) : Colors.transparent),
          ),
        ],
      ),
    );
    if (!inMonth) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _day = date);
      },
      child: cell,
    );
  }
}

/// Pinned header that reports how far it has folded (0 open → 1 at [min]).
class _Collapsing extends SliverPersistentHeaderDelegate {
  _Collapsing({required this.min, required this.max, required this.builder});
  final double min, max;
  final Widget Function(double t) builder;

  @override
  double get minExtent => min;
  @override
  double get maxExtent => max;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => builder((shrinkOffset / (max - min)).clamp(0.0, 1.0));
  @override
  bool shouldRebuild(_Collapsing old) => true;
}
