import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'analytics.dart';
import 'data.dart';
import 'item_tile.dart';
import 'screens.dart';
import 'ui.dart';

class _Tab extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final tabProvider = NotifierProvider<_Tab, int>(_Tab.new);

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final provider = sourceFilters[ref.watch(sourceFilterProvider)];
    return Scaffold(
      body: Ambient(
        color: providerColors[provider] ?? kAccent,
        child: Stack(children: [
          IndexedStack(
            index: tab,
            children: const [DashboardTab(), TrialsCalendarTab(), AccountsTab(), AnalyticsTab()],
          ),
          // Floating chrome: the only real glass in the app.
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(child: _TabBar(tab: tab, onTap: ref.read(tabProvider.notifier).set)),
                const SizedBox(width: 12),
                Pressable(
                  onTap: () => showAddSheet(context),
                  child: const Glass(
                    oval: true,
                    child: SizedBox.square(dimension: 64, child: Icon(Icons.add_rounded, size: 30, semanticLabel: 'Add')),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onTap});
  final int tab;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.calendar_month_rounded, 'Calendar'),
    (Icons.account_balance_rounded, 'Accounts'),
    (Icons.insights_rounded, 'Insights'),
  ];

  @override
  Widget build(BuildContext context) => Glass(
        radius: 32,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 12) / _items.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: springBounce,
                left: 6 + w * tab,
                top: 6,
                bottom: 6,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(26)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == tab,
                        label: _items[i].$2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(i);
                          },
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_items[i].$1, size: 22, color: i == tab ? kText : kMuted),
                            const SizedBox(height: 2),
                            Text(_items[i].$2,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: i == tab ? kText : kMuted)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ]);
          }),
        ),
      );
}

/// Pinned top bar that turns into glass only once content scrolls underneath it.
class TopBar extends ConsumerWidget {
  const TopBar({super.key, required this.scrolled, this.title});
  final bool scrolled;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kAccent, Color(0xFF3D7BFF)])),
              child: const Icon(Icons.person_rounded, size: 20),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: scrolled && title != null ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(title ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              initialValue: base,
              color: kSurfaceHi,
              tooltip: 'Base currency',
              onSelected: setBaseCurrency,
              itemBuilder: (_) => [for (final c in ['GBP', 'USD', 'EUR', 'GHS']) PopupMenuItem(value: c, child: Text(c))],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Text(base, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Icon(Icons.expand_more_rounded, size: 16, color: kMuted),
                ]),
              ),
            ),
            IconButton(
              tooltip: 'Upcoming',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => showSheet(context, const AlertsSheet()),
            ),
          ]),
        ),
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: scrolled
          ? Glass(key: const ValueKey('glass'), radius: 0, tint: const Color(0x9907080C), child: bar)
          : KeyedSubtree(key: const ValueKey('flat'), child: bar),
    );
  }
}

/// Scroll page with a pinned [TopBar] whose glass appears on scroll.
class TabPage extends StatefulWidget {
  const TabPage({super.key, required this.slivers, this.title, this.onRefresh});
  final List<Widget> slivers;
  final String? title;
  final Future<void> Function()? onRefresh;
  @override
  State<TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<TabPage> {
  bool _scrolled = false;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 56;
    Widget scroll = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final s = n.metrics.pixels > 4;
        if (s != _scrolled) setState(() => _scrolled = s);
        return false;
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: top)),
          ...widget.slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(edgeOffset: top, color: kText, backgroundColor: kSurfaceHi, onRefresh: widget.onRefresh!, child: scroll);
    }
    return Stack(children: [
      scroll,
      Positioned(top: 0, left: 0, right: 0, child: TopBar(scrolled: _scrolled, title: widget.title)),
    ]);
  }
}

// ───────── Home ─────────

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final all = ref.watch(itemsProvider).value ?? [];
    final sources = ref.watch(sourcesProvider).value ?? [];
    final items = ref.watch(filteredItemsProvider);
    final active = all.where((i) => i.status == 'active');
    final out = active.where((i) => i.type != 'income').fold(0.0, (s, i) => s + i.monthlyBase);
    final income = active.where((i) => i.type == 'income').fold(0.0, (s, i) => s + i.monthlyBase);
    final balance = sources.fold(0.0, (s, a) => s + (a.baseBalance ?? 0));
    final trials = items.where((i) => i.isTrial && i.trialEnd != null && i.trialEnd!.isAfter(DateTime.now())).toList();

    return TabPage(
      title: 'Home',
      onRefresh: () async {
        try {
          await syncBanks();
        } catch (e) {
          if (context.mounted) showError(context, 'Sync failed: ${functionError(e)}');
        }
      },
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            label: sources.isEmpty ? 'Monthly outgoings' : 'Total balance',
            value: sources.isEmpty ? out : balance,
            base: base,
            income: income,
            out: out,
          ),
        ),
        const SliverToBoxAdapter(child: _QuickActions()),
        const SliverToBoxAdapter(child: ShortfallAlerts()),
        if (sources.isNotEmpty) const SliverToBoxAdapter(child: AccountStrip()),
        if (all.isNotEmpty) SliverToBoxAdapter(child: _NextDays(items: items, base: base)),
        if (trials.isNotEmpty) SliverToBoxAdapter(child: _TrialRings(trials, base)),
        if (all.isEmpty) const SliverToBoxAdapter(child: _EmptyState()) else ..._upcoming(ref, items),
      ],
    );
  }

  List<Widget> _upcoming(WidgetRef ref, List<FinancialItem> items) {
    final now = DateTime.now();
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    final groups = <String, List<FinancialItem>>{'Next 24 hours': [], 'This week': [], 'Later this month': [], 'Later': []};
    for (final i in items) {
      final d = i.dueAt?.difference(now);
      groups[d == null
              ? 'Later'
              : d.inHours < 24
                  ? 'Next 24 hours'
                  : d.inDays < 7
                      ? 'This week'
                      : i.dueAt!.isBefore(endOfMonth)
                          ? 'Later this month'
                          : 'Later']!
          .add(i);
    }
    return [
      const SliverToBoxAdapter(child: SectionHeader('Upcoming')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Segmented(
            labels: const ['All', 'Trials', 'Subs', 'Pay later', 'Income'],
            selected: ref.watch(typeFilterProvider),
            onSelect: ref.read(typeFilterProvider.notifier).set,
          ),
        ),
      ),
      if (items.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Nothing matches this filter.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ),
        ),
      for (final e in groups.entries.where((e) => e.value.isNotEmpty)) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(children: [
              Text(e.key.toUpperCase(), style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const Spacer(),
              Text(
                money(e.value.where((i) => i.type != 'income').fold(0.0, (s, i) => s + (i.baseAmount ?? 0)),
                    ref.watch(baseCurrencyProvider).value ?? 'GBP'),
                style: const TextStyle(color: kMuted, fontSize: 12, fontFeatures: tabular),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: ItemGroup(e.value).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, curve: springOut)),
      ],
    ];
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
            _Pill(icon: Icons.south_west_rounded, color: kMint, text: '${compactMoney(income, base)} in / mo'),
            _Pill(icon: Icons.north_east_rounded, color: kCrimson, text: '${compactMoney(out, base)} out / mo'),
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

class _QuickActions extends ConsumerWidget {
  const _QuickActions();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget action(IconData icon, String text, VoidCallback onTap) => Pressable(
          onTap: onTap,
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: kSurfaceHi, shape: BoxShape.circle, border: Border.all(color: kLine)),
              child: Icon(icon, size: 24),
            ),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        action(Icons.add_rounded, 'Add', () => showSheet(context, const ManualItemForm())),
        action(Icons.document_scanner_outlined, 'Scan', () => scanReceipt(context)),
        action(Icons.link_rounded, 'Connect', () => ref.read(tabProvider.notifier).set(2)),
        action(Icons.donut_large_rounded, 'Insights', () => ref.read(tabProvider.notifier).set(3)),
      ]),
    );
  }
}

class _Dismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void add(String id) => state = {...state, id};
}

final _dismissedShortfalls = NotifierProvider<_Dismissed, Set<String>>(_Dismissed.new);

class ShortfallAlerts extends ConsumerWidget {
  const ShortfallAlerts({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(_dismissedShortfalls);
    final list = (ref.watch(shortfallProvider).value ?? []).where((s) => !hidden.contains(s.sourceId));
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    return Column(children: [
      for (final s in list)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Surface(
            color: Color.alphaBlend((s.days <= 2 ? kCrimson : kAmber).withValues(alpha: 0.10), kSurface),
            border: (s.days <= 2 ? kCrimson : kAmber).withValues(alpha: 0.3),
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: s.days <= 2 ? kCrimson : kAmber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Top up ${providerLabels[s.provider]} by ${money(s.shortfall, base)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                  const SizedBox(height: 4),
                  Text(
                    '${money(s.due, base)} in renewals and expiring trials due within ${s.days == 0 ? 'today' : '${s.days} day${s.days == 1 ? '' : 's'}'}, '
                    'but the balance is ${money(s.balance, base)}.',
                    style: const TextStyle(color: kMuted, fontSize: 13, height: 1.35, fontFeatures: tabular),
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: kMuted),
                onPressed: () => ref.read(_dismissedShortfalls.notifier).add(s.sourceId),
              ),
            ]),
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, curve: springOut),
    ]);
  }
}

/// Account cards double as the source filter: tap to focus, tap again to clear.
class AccountStrip extends ConsumerWidget {
  const AccountStrip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final selected = sourceFilters[ref.watch(sourceFilterProvider)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Accounts', trailing: selected == null ? null : _ClearFilter(onTap: () => ref.read(sourceFilterProvider.notifier).set(0))),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: sources.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final s = sources[i];
            final c = providerColors[s.provider] ?? kAccent;
            final on = selected == s.provider;
            return Pressable(
              onTap: () => ref.read(sourceFilterProvider.notifier).set(on ? 0 : sourceFilters.indexOf(s.provider)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 168,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: on ? c : kLine, width: on ? 1.5 : 1),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.alphaBlend(c.withValues(alpha: 0.22), kSurface), kSurface],
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(providerLabels[s.provider]!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(s.currency, style: caption),
                  ]),
                  const Spacer(),
                  Text(money(s.balance, s.currency), style: display(20)),
                  Text(
                    s.currency != base && s.baseBalance != null ? '≈ ${money(s.baseBalance!, base)}' : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: caption,
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

class _ClearFilter extends StatelessWidget {
  const _ClearFilter({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: const Row(children: [
          Text('Show all', style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          Icon(Icons.close_rounded, size: 16, color: kAccent),
        ]),
      );
}

/// 14-day strip: each day shows its charges as provider-coloured dots and the day total.
class _NextDays extends ConsumerWidget {
  const _NextDays({required this.items, required this.base});
  final List<FinancialItem> items;
  final String base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = {for (final s in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) s.id: s.provider};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final charges = chargesBetween(items, today, today.add(const Duration(days: 14)));
    final total = charges.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Next 14 days', trailing: Text('${money(total, base)} out', style: const TextStyle(color: kMuted, fontSize: 13, fontFeatures: tabular))),
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 14,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, k) {
            final day = today.add(Duration(days: k));
            final onDay = charges.where((c) => DateUtils.isSameDay(c.date, day)).toList();
            final spend = onDay.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);
            final isToday = k == 0;
            return Pressable(
              onTap: () {
                if (onDay.isEmpty) return;
                showSheet(context, DaySheet(day: day, items: onDay.map((c) => c.item).toList()));
              },
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isToday ? kText : kSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isToday ? kText : kLine),
                ),
                child: Column(children: [
                  Text(DateFormat('E').format(day).substring(0, 2), style: TextStyle(fontSize: 11, color: isToday ? kBg.withValues(alpha: 0.6) : kMuted)),
                  const SizedBox(height: 2),
                  Text('${day.day}', style: display(18, color: isToday ? kBg : kText)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 6,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final c in onDay.take(4))
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.amount > 0 ? kMint : (providerColors[sources[c.item.sourceId]] ?? kAccent),
                          ),
                        ),
                    ]),
                  ),
                  const Spacer(),
                  Text(
                    spend == 0 ? '' : compactMoney(spend, base),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isToday ? kBg : kMuted, fontFeatures: tabular),
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
        Flexible(child: SingleChildScrollView(child: ItemGroup(items))),
        const SizedBox(height: 16),
      ]);
}

class _TrialRings extends StatelessWidget {
  const _TrialRings(this.trials, this.base);
  final List<FinancialItem> trials;
  final String base;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader('Free trials ending', trailing: Text('${trials.length}', style: label)),
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
              return Surface(
                onTap: () => showSheet(context, DaySheet(day: t.trialEnd!, items: [t])),
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 132,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Ring(
                      progress: t.trialProgress,
                      color: urgent ? kCrimson : kAccent,
                      center: Text(left.inDays > 0 ? '${left.inDays}d' : '${left.inHours}h', style: display(18)),
                    ),
                    const Spacer(),
                    Text(t.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      t.baseAmount == null || t.postTrialAmount == null ? 'Charge unknown' : 'then ${money(t.baseAmount!, base)}',
                      style: TextStyle(color: urgent ? kCrimson : kMuted, fontSize: 12, fontFeatures: tabular),
                    ),
                    LiveCountdown(t.trialEnd!, style: caption),
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
        child: SizedBox.square(dimension: 64, child: Center(child: center)),
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
                for (final (dx, a, c) in [(-34.0, -0.18, kAccent), (34.0, 0.18, kMint), (0.0, 0.0, const Color(0xFF3D7BFF))])
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
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, curve: springOut);
}

// ───────── Add ─────────

Future<void> scanReceipt(BuildContext context) async {
  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
  if (img == null || !context.mounted) return;
  showToast(context, 'Reading receipt…', icon: Icons.auto_awesome_rounded, tone: kAccent, duration: const Duration(seconds: 20));
  try {
    final res = await parseReceipt({'image_base64': base64Encode(await img.readAsBytes()), 'media_type': img.mimeType ?? 'image/jpeg'});
    if (!context.mounted) return;
    final item = res['item'];
    item != null
        ? showToast(context, 'Added ${item['merchant_name']}')
        : showToast(context, 'No trial or subscription found in that image', icon: Icons.info_rounded, tone: kAmber);
  } catch (e) {
    if (context.mounted) showError(context, 'Scan failed: ${functionError(e)}');
  }
}

Future<void> showAddSheet(BuildContext context) => showSheet(context, const _AddSheet());

class _AddSheet extends StatelessWidget {
  const _AddSheet();
  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, Color c, String title, String sub, VoidCallback onTap) => Surface(
          color: kSurfaceHi,
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(sub, style: caption),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: kFaint),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 16), child: Text('Add', style: display(24))),
        option(Icons.document_scanner_outlined, kAccent, 'Scan a receipt', 'AI reads trial dates and the post-trial charge', () {
          // The sheet's context dies on pop; continue from the navigator's.
          final nav = Navigator.of(context)..pop();
          scanReceipt(nav.context);
        }),
        const SizedBox(height: 10),
        option(Icons.edit_outlined, const Color(0xFF3D7BFF), 'Add manually', 'Subscription, trial, Pay in 3 or income', () {
          final nav = Navigator.of(context)..pop();
          showSheet(nav.context, const ManualItemForm());
        }),
        const SizedBox(height: 10),
        const InboundEmailTile(),
      ]),
    );
  }
}
