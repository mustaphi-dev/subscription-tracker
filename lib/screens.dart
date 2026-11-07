import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brands.dart';
import 'countries.dart';
import 'data.dart';
import 'home.dart';
import 'item_tile.dart';
import 'ui.dart';

// ───────── Calendar ─────────

class TrialsCalendarTab extends ConsumerStatefulWidget {
  const TrialsCalendarTab({super.key});
  @override
  ConsumerState<TrialsCalendarTab> createState() => _CalendarState();
}

const _rowH = 52.0, _labelsH = 26.0, _titleH = 108.0; // title = 20 padding + ~44 month + ~30 total, with headroom for larger text settings
const _origin = 1200; // PageView index of the current month; swiping back is bounded at 100 years.

class _CalendarState extends ConsumerState<TrialsCalendarTab> {
  final _pages = PageController(initialPage: _origin);
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
      _day = m.year == today.year && m.month == today.month ? today : m;
    });
  }

  void _goToday() => _pages.animateToPage(_origin, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final items = ref.watch(itemsProvider).value ?? [];
    final today = DateUtils.dateOnly(DateTime.now());
    final monthOut = chargesBetween(items, _month, DateTime(_month.year, _month.month + 1)).where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);
    final onDay = chargesBetween(items, _day, DateTime(_day.year, _day.month, _day.day + 1)).where((c) => DateUtils.isSameDay(c.date, _day)).toList();
    final trials = items.where((i) => i.isTrial && i.status != 'cancelled' && i.trialEnd != null && i.trialEnd!.isAfter(DateTime.now())).toList();

    final top = MediaQuery.of(context).padding.top + 56;
    final sel = (_month.weekday - 1 + _day.day - 1) ~/ 7; // grid row holding the selected day

    // How far the grid has folded (0 → 1); the sheet only becomes a sheet as this rises.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0) _fold.value = (n.metrics.pixels / (_titleH + 5 * _rowH)).clamp(0.0, 1.0);
        return false;
      },
      child: TabPage(
        title: DateFormat('MMMM').format(_month),
        padTop: false,
        padBottom: false,
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
                padding: const EdgeInsets.only(bottom: 140),
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
                              money(onDay.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount), base),
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
    final isCurrent = _month.year == today.year && _month.month == today.month;
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
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.8, 1],
                        colors: [kBg, kBg, Color(0x0007080C)],
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
                        // Slide the grid up as it folds so the selected week ends on top.
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
    final current = month.year == _month.year && month.month == _month.month;

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

// ───────── Accounts ─────────

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final total = sources.fold(0.0, (s, a) => s + (a.baseBalance ?? 0));
    ref.watch(countryProvider); // keeps the country loaded for _syncUnavailable

    return TabPage(
      title: 'Accounts',
      onRefresh: () async {
        if (!sources.any((s) => !s.isManual)) return;
        try {
          await syncBanks();
        } catch (e) {
          if (context.mounted) showError(context, 'Couldn\'t refresh your banks. Try again in a moment.', e);
        }
      },
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total balance', style: TextStyle(color: kMuted, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                BigMoney(total, base, size: 52),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              children: [
                // The plus searches every bank in your country.
                Surface(
                  onTap: () {
                    final why = _syncUnavailable(ref);
                    why == null ? showSheet(context, const _BankPicker()) : showError(context, why);
                  },
                  child: Row(
                    children: [
                      // Overlapping logos hint at what can be added.
                      SizedBox(
                        width: 36 + 3 * 22, // 32px logo + 2px ring each side
                        height: 36,
                        child: Stack(
                          children: [
                            for (final (i, b) in const ['Monzo', 'Barclays', 'GCB', 'MTN MoMo'].indexed)
                              Positioned(
                                left: i * 22,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(13)),
                                  child: MerchantAvatar(b, size: 32),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add an account', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('Any bank, card or wallet', style: caption),
                          ],
                        ),
                      ),
                      // Same Liquid Glass as the bottom nav's add button.
                      const Glass(
                        oval: true,
                        child: SizedBox.square(dimension: 40, child: Icon(CupertinoIcons.plus, size: 22)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader('Connect automatically')),
        // Common banks connect in one tap.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Surface(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tap a bank to link it in seconds.',
                    style: TextStyle(color: kMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final b in _commonBanks) _BankTile(b, _BankMark(b, providerColorFor(b), size: 44), () => _connectByName(context, ref, b)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (sources.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Your accounts')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (k, accounts) in <String, List<PaymentSource>>{for (final s in sources) s.bank: [for (final t in sources) if (t.bank == s.bank) t]}.values.indexed) ...[
                      if (k > 0) const Divider(height: 1, indent: 70, color: kLine),
                      _BankRow(accounts, base),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One bank with all its accounts (current, savings…) folded into a single row and total.
class _BankRow extends StatelessWidget {
  const _BankRow(this.accounts, this.base);
  final List<PaymentSource> accounts;
  final String base;
  @override
  Widget build(BuildContext context) {
    final first = accounts.first;
    final total = accounts.fold(0.0, (t, a) => t + (a.baseBalance ?? 0));
    return Pressable(
      scale: 0.99,
      onTap: () => showSheet(context, _BankSheet(accounts, base)),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _BankMark(first.bank, first.color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(first.bank, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  accounts.map((a) => a.name).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ],
            ),
          ),
          Text(money(total, base), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_right, color: kFaint, size: 18),
        ],
      ),
      ),
    );
  }
}

/// A bank's accounts, with the one action that matters: unlink it (or remove it, if added by hand).
class _BankSheet extends StatelessWidget {
  const _BankSheet(this.accounts, this.base);
  final List<PaymentSource> accounts;
  final String base;
  @override
  Widget build(BuildContext context) {
    final bank = accounts.first.bank;
    final manual = accounts.every((a) => a.isManual);
    Future<void> remove() async {
      final ok = await showSheet<bool>(
        context,
        Builder(
          builder: (ctx) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(manual ? 'Remove $bank?' : 'Unlink $bank?', textAlign: TextAlign.center, style: display(22)),
              const SizedBox(height: 8),
              Text(
                manual
                    ? 'Its balance goes from your total. Subscriptions you track stay, without an account.'
                    : 'We\'ll stop reading $bank and remove its ${accounts.length == 1 ? 'account' : '${accounts.length} accounts'} here. '
                        'Subscriptions found from it stay. You can connect it again any time.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kCrimson, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(manual ? 'Remove' : 'Unlink'),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: kText, minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep it', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
      if (ok != true || !context.mounted) return;
      try {
        manual ? await removeAccounts(accounts.map((a) => a.id)) : await unlinkBank(bank);
        if (context.mounted) {
          Navigator.of(context).pop();
          showToast(context, manual ? '$bank removed' : '$bank unlinked');
        }
      } catch (e) {
        if (context.mounted) showError(context, 'Couldn\'t remove $bank. Try again.', e);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _BankMark(bank, accounts.first.color, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bank, style: display(20)),
                Text(manual ? 'Added manually' : 'Linked', style: caption),
              ]),
            ),
            Text(money(accounts.fold(0.0, (t, a) => t + (a.baseBalance ?? 0)), base), style: display(18)),
          ]),
          const SizedBox(height: 16),
          Surface(
            padding: EdgeInsets.zero,
            color: kSurfaceHi,
            child: Column(children: [
              for (final (k, a) in accounts.indexed) ...[
                if (k > 0) const Divider(height: 1, color: kLine),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(money(a.balance, a.currency), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                      if (a.currency != base && a.baseBalance != null) Text('≈ ${money(a.baseBalance!, base)}', style: caption),
                    ]),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: kCrimson, side: BorderSide(color: kCrimson.withValues(alpha: 0.4))),
            onPressed: remove,
            child: Text(manual ? 'Remove account' : 'Unlink $bank'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

Future<void> _connect(BuildContext context, String bank) async {
  try {
    await launchUrl(Uri.parse(await connectBank(bank)), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t connect $bank. Try again.', e);
  }
}

/// Why bank sync can't be used here, or null when it can. Sync follows the country on your profile.
String? _syncUnavailable(WidgetRef ref) {
  final country = countryByCode(ref.read(countryProvider).value);
  if (country == null) return 'Set your country in Profile to connect a bank.';
  return country.bankLinking ? null : 'Bank sync isn\'t available in ${country.name} yet.';
}

/// Four well-known banks shown on the Accounts card.
const _commonBanks = ['Revolut', 'Wise', 'Lloyds', 'PayPal'];

/// Connects [name] (e.g. "Lloyds") using the provider's own name for it (e.g. "Lloyds Bank").
Future<void> _connectByName(BuildContext context, WidgetRef ref, String name) async {
  final why = _syncUnavailable(ref);
  if (why != null) return showError(context, why);
  // A tap before the list loads waits for it instead of failing.
  final all = await ref.read(banksProvider.future).catchError((_) => <String>[]);
  final bank = all.where((b) => b.toLowerCase().startsWith(name.toLowerCase())).firstOrNull;
  if (!context.mounted) return;
  if (bank == null) {
    return showError(context, all.isEmpty ? 'Bank linking isn\'t available right now.' : '$name can\'t be connected yet.');
  }
  await _connect(context, bank);
}

class _BankTile extends StatelessWidget {
  const _BankTile(this.label, this.mark, this.onTap);
  final String label;
  final Widget mark;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Pressable(
      onTap: onTap,
      child: Column(
        children: [
          mark,
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}

/// Searchable list of every bank the provider supports in the user's country.
class _BankPicker extends ConsumerStatefulWidget {
  const _BankPicker();
  @override
  ConsumerState<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends ConsumerState<_BankPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final shown = (banks.value ?? []).where((b) => b.toLowerCase().contains(_q.toLowerCase())).toList();
    final mq = MediaQuery.of(context);
    return SizedBox(
      // 60% of the screen, or 70% of what's left above the keyboard, so the title never reaches the status bar.
      height: math.min(mq.size.height * 0.6, (mq.size.height - mq.viewInsets.bottom) * 0.7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Connect your bank', style: display(20)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassSearchField(hint: 'Search banks', onChanged: (v) => setState(() => _q = v)),
          ),
          const SizedBox(height: 8),
          if (!banks.isLoading && shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                banks.hasError ? 'Couldn\'t load banks right now.' : (_q.isEmpty ? 'No banks available to connect yet.' : 'No banks match "$_q".'),
                textAlign: TextAlign.center,
                style: caption,
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              itemCount: shown.length,
              itemBuilder: (_, i) => Pressable(
                scale: 0.99,
                onTap: () async {
                  await _connect(context, shown[i]);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      _BankMark(shown[i], providerColorFor(shown[i]), size: 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(shown[i], style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      const Icon(CupertinoIcons.chevron_right, color: kFaint, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankMark extends StatelessWidget {
  const _BankMark(this.name, this.color, {this.size = 40});
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => LogoTile(
    name,
    size: size,
    fallback: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.45),
      ),
    ),
  );
}

// ───────── Sheets ─────────

class ManualItemForm extends ConsumerStatefulWidget {
  const ManualItemForm({super.key});
  @override
  ConsumerState<ManualItemForm> createState() => _ManualItemFormState();
}

class _ManualItemFormState extends ConsumerState<ManualItemForm> {
  final _merchant = TextEditingController();
  final _amount = TextEditingController();
  final _installTotal = TextEditingController(text: '3');
  String _type = 'subscription', _currency = 'GBP', _cycle = 'monthly';
  String? _sourceId;
  DateTime _date = DateTime.now().add(const Duration(days: 7));

  static const _types = ['subscription', 'free_trial', 'installment', 'income'];

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text);
    if (_merchant.text.trim().isEmpty || amount == null) {
      showError(context, 'Add a name and an amount');
      return;
    }
    final trial = _type == 'free_trial';
    final installments = int.tryParse(_installTotal.text);
    try {
      await addItem({
        'item_type': _type,
        'merchant_name': _merchant.text.trim(),
        'original_amount': trial ? 0 : amount,
        'original_currency': _currency,
        'post_trial_amount': trial ? amount : null,
        'billing_cycle': _cycle,
        'payment_source_id': _sourceId,
        'next_renewal_date': DateFormat('yyyy-MM-dd').format(_date),
        if (trial) 'trial_end_date': _date.toUtc().toIso8601String(),
        if (_type == 'installment') ...{'installment_total_count': installments, 'installment_remaining_balance': amount * (installments ?? 0)},
      });
    } catch (e) {
      if (mounted) showError(context, 'Couldn\'t save that. Try again.', e);
      return;
    }
    if (!mounted) return;
    showToast(context, 'Added ${_merchant.text.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    Widget field(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: caption),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
    Widget box(Widget child) => Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(14)),
      child: child,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text('New item', style: display(24)),
          ),
          Segmented(
            labels: const ['Subscription', 'Trial', 'Pay later', 'Income'],
            selected: _types.indexOf(_type),
            onSelect: (i) => setState(() => _type = _types[i]),
          ),
          const SizedBox(height: 16),
          field(
            'Name',
            TextField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Netflix'),
            ),
          ),
          field(
            switch (_type) {
              'free_trial' => 'Charge after the trial',
              'installment' => 'Each payment',
              'income' => 'Amount received',
              _ => 'Amount',
            },
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFeatures: tabular),
                    decoration: const InputDecoration(hintText: '0.00'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: SelectField<String>(
                    title: 'Currency',
                    options: currencyOptions(const ['GBP', 'USD', 'EUR', 'GHS']),
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v),
                  ),
                ),
              ],
            ),
          ),
          if (_type == 'installment') field('Number of payments', TextField(controller: _installTotal, keyboardType: TextInputType.number)),
          Row(
            children: [
              Expanded(
                child: field(
                  'Repeats',
                  SelectField<String>(
                    title: 'Repeats',
                    options: const [
                      ('weekly', 'Weekly', 'Every 7 days'),
                      ('monthly', 'Monthly', 'Same date each month'),
                      ('quarterly', 'Quarterly', 'Every 3 months'),
                      ('yearly', 'Yearly', 'Once a year'),
                      ('once', 'One-off', 'Doesn\'t repeat'),
                    ],
                    value: _cycle,
                    onChanged: (v) => setState(() => _cycle = v),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: field(
                  _type == 'free_trial' ? 'Trial ends' : 'Next date',
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime(2100));
                      if (d != null) setState(() => _date = d);
                    },
                    child: box(Text(DateFormat('d MMM y').format(_date))),
                  ),
                ),
              ),
            ],
          ),
          field(
            _type == 'income' ? 'Paid into' : 'Paid from',
            SelectField<String>(
              title: _type == 'income' ? 'Paid into' : 'Paid from',
              hint: sources.isEmpty ? 'No accounts yet' : 'Choose an account',
              options: [for (final s in sources) (s.id, s.bank, '${s.name} · ${money(s.balance, s.currency)}')],
              value: _sourceId,
              onChanged: (v) => setState(() => _sourceId = v),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

// ───────── Confirm detected trial (push deep-link) ─────────

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
