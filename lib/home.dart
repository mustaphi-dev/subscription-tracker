import 'dart:convert';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
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

/// True once the current tab is scrolled away from the top: the bottom bar shrinks and drops its labels.
class _Compact extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) {
    if (v != state) state = v;
  }
}

final navCompactProvider = NotifierProvider<_Compact, bool>(_Compact.new);

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final compact = ref.watch(navCompactProvider);
    return Scaffold(
      body: Ambient(
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
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: compact ? 1 : 0),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (_, c, _) => LayoutBuilder(builder: (_, box) {
                  final h = lerpDouble(64, 48, c)!;
                  // Full width when open; trims to 80% when compact so icons keep comfortable tap targets.
                  final full = box.maxWidth - 12 - h;
                  final w = lerpDouble(full, full * 0.8, c)!;
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: w,
                      child: _TabBar(
                        tab: tab,
                        height: h,
                        labels: 1 - c,
                        onTap: (i) {
                          ref.read(navCompactProvider.notifier).set(false);
                          ref.read(tabProvider.notifier).set(i);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Pressable(
                      onTap: () => showSheet(context, const _AddSheet()),
                      child: Glass(
                        oval: true,
                        child: SizedBox.square(
                          dimension: h,
                          child: Icon(CupertinoIcons.plus, size: lerpDouble(30, 26, c), semanticLabel: 'Add'),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onTap, required this.height, required this.labels});
  final int tab;
  final ValueChanged<int> onTap;
  final double height;

  /// 1 = labels fully shown, 0 = icons only.
  final double labels;

  static const _items = [
    (CupertinoIcons.house, 'Home'),
    (CupertinoIcons.calendar, 'Calendar'),
    (CupertinoIcons.creditcard, 'Accounts'),
    (CupertinoIcons.chart_bar, 'Insights'),
  ];

  @override
  Widget build(BuildContext context) => Glass(
        radius: height / 2,
        child: SizedBox(
          height: height,
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
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(height / 2 - 6)),
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
                            // Collapses its own height as well as fading, so the icon re-centres.
                            ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: labels,
                                child: Opacity(
                                  opacity: labels,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(_items[i].$2,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: i == tab ? kText : kMuted)),
                                  ),
                                ),
                              ),
                            ),
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
    final alert = ref.watch(alertsProvider).isNotEmpty;
    final bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Semantics(
              button: true,
              label: 'Profile and settings',
              child: Pressable(onTap: () => context.push('/profile'), child: const ProfileAvatar(size: 36)),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: scrolled && title != null ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(title ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const Spacer(),
            CurrencyPill(current: base, onChanged: setBaseCurrency),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Upcoming',
              child: Pressable(
                onTap: () => showDraggableSheet(context, (scroll) => AlertsSheet(scroll: scroll)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Badge(isLabelVisible: alert, smallSize: 8, backgroundColor: kCrimson, child: const FaIcon(FontAwesomeIcons.bell, size: 20)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    // A background-coloured scrim that fades out past the bar, so there's no visible edge or "section".
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: -36,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: scrolled ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.55, 1],
                  colors: [kBg, Color(0xE607080C), Color(0x0007080C)],
                ),
              ),
            ),
          ),
        ),
      ),
      bar,
    ]);
  }
}

/// Scroll page with a pinned [TopBar] whose glass appears on scroll.
class TabPage extends ConsumerStatefulWidget {
  const TabPage({super.key, required this.slivers, this.title, this.onRefresh, this.padTop = true, this.padBottom = true});
  final List<Widget> slivers;
  final String? title;
  final Future<void> Function()? onRefresh;

  /// False when the first sliver is a pinned header that reserves the top-bar space itself.
  final bool padTop;

  /// False when the last sliver already runs to the bottom of the screen (e.g. a sheet).
  final bool padBottom;
  @override
  ConsumerState<TabPage> createState() => _TabPageState();
}

class _TabPageState extends ConsumerState<TabPage> {
  bool _scrolled = false;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 56;
    Widget scroll = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth != 0) return false; // ignore the horizontal strips inside the page
        final px = n.metrics.pixels;
        if ((px > 4) != _scrolled) setState(() => _scrolled = px > 4);
        ref.read(navCompactProvider.notifier).set(px > 60);
        return false;
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          if (widget.padTop) SliverToBoxAdapter(child: SizedBox(height: top)),
          ...widget.slivers,
          if (widget.padBottom) const SliverToBoxAdapter(child: SizedBox(height: 140)),
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
          if (context.mounted) showError(context, 'Couldn\'t refresh your banks. Try again in a moment.', e);
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
        if (all.isNotEmpty) SliverToBoxAdapter(child: _NextDays(items: items, base: base)),
        if (trials.isNotEmpty) SliverToBoxAdapter(child: _TrialRings(trials, base)),
        if (all.isEmpty) const SliverToBoxAdapter(child: _EmptyState()) else ...upcomingSlivers(context, ref, items, limit: 6),
      ],
    );
  }

}

/// Upcoming charges grouped by when they're due. With [limit], shows only the soonest few plus a "See all" link.
/// [controls] replaces the type tabs, e.g. with the full page's search and filter.
List<Widget> upcomingSlivers(BuildContext context, WidgetRef ref, List<FinancialItem> items, {int? limit, Widget? controls}) {
    final more = limit != null && items.length > limit;
    final all = items;
    if (more) items = items.take(limit).toList(); // already sorted soonest first
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
      if (limit != null) const SliverToBoxAdapter(child: SectionHeader('Upcoming')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: controls ??
              Segmented(
                labels: _typeLabels,
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
        SliverToBoxAdapter(child: ItemGroup(e.value, sheet: controls != null).fadeRise()),
      ],
      if (more)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton(onPressed: () => context.push('/upcoming'), child: Text('See all ${all.length}')),
          ),
        ),
    ];
}

const _typeLabels = ['All', 'Trials', 'Subs', 'Pay later', 'Income'];

/// Every upcoming item, reached from "See all" on Home. Search by name; the filter shares Home's type tabs.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});
  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final type = ref.watch(typeFilterProvider);
    final items = ref.watch(filteredItemsProvider).where((i) => i.merchant.toLowerCase().contains(_q.toLowerCase())).toList();
    final controls = Row(children: [
      Expanded(child: GlassSearchField(hint: 'Search', onChanged: (v) => setState(() => _q = v))),
      const SizedBox(width: 10),
      Semantics(
        button: true,
        label: 'Filter: ${_typeLabels[type]}',
        child: Pressable(
          onTap: () async {
            final picked = await pickFromSheet<int>(
              context,
              title: 'Show',
              options: [for (final (k, l) in _typeLabels.indexed) (k, l, null)],
              selected: type,
            );
            if (picked != null) ref.read(typeFilterProvider.notifier).set(picked);
          },
          child: Glass(
            radius: 24,
            tint: type == 0 ? const Color(0x1AFFFFFF) : kAccent.withValues(alpha: 0.25),
            child: Container(
              height: 48,
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.slider_horizontal_3, size: 18),
                if (type != 0) ...[
                  const SizedBox(width: 6),
                  Text(_typeLabels[type], style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ),
        ),
      ),
    ]);
    return Scaffold(
      body: Ambient(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 24, 12),
                  child: Row(children: [
                    const GlassBackButton(),
                    const SizedBox(width: 12),
                    Text('Upcoming', style: display(20)),
                  ]),
                ),
              ),
            ),
            ...upcomingSlivers(context, ref, items, controls: controls),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
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

/// Notifications the user cleared, kept on the device. Keys include the due date, so the next
/// renewal or a new shortfall shows up again.
class _Dismissed extends Notifier<Set<String>> {
  static const _storage = FlutterSecureStorage();
  @override
  Set<String> build() {
    _storage.read(key: 'dismissed_alerts').then((v) {
      if (v != null) state = {...state, ...(jsonDecode(v) as List).cast<String>()};
    }).catchError((_) {}); // unreadable storage just means nothing was cleared yet
    return {};
  }

  // ponytail: keys accumulate forever; prune past due dates if this list ever grows noticeably.
  void addAll(Iterable<String> keys) {
    state = {...state, ...keys};
    _storage.write(key: 'dismissed_alerts', value: jsonEncode(state.toList()));
  }

  void removeAll(Iterable<String> keys) {
    state = state.difference(keys.toSet());
    _storage.write(key: 'dismissed_alerts', value: jsonEncode(state.toList()));
  }
}

final _dismissedAlerts = NotifierProvider<_Dismissed, Set<String>>(_Dismissed.new);

typedef Alert = ({String key, String logo, Color color, String title, String sub});

/// What the bell shows: low balances, trials ending within a week, and payments due in 24 hours.
final alertsProvider = Provider<List<Alert>>((ref) {
  final hidden = ref.watch(_dismissedAlerts);
  final banks = {for (final a in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) a.id: a.bank};
  final now = DateTime.now();
  final items = (ref.watch(itemsProvider).value ?? []).where((i) => i.status == 'active' && i.dueAt != null && i.dueAt!.isAfter(now));
  final all = <Alert>[
    for (final s in ref.watch(shortfallProvider).value ?? <Shortfall>[])
      (
        key: 'short:${s.sourceId}:${s.due}',
        logo: banks[s.sourceId] ?? s.provider,
        color: kCrimson,
        title: 'Top up ${banks[s.sourceId] ?? 'account'} by ${money(s.shortfall, s.currency)}',
        sub: '${money(s.due, s.currency)} due ${s.days == 0 ? 'today' : 'within ${s.days} day${s.days == 1 ? '' : 's'}'}, balance ${money(s.balance, s.currency)}',
      ),
    // Same window as the push reminders.
    for (final i in items.where((i) => i.isTrial && i.trialEnd!.difference(now).inDays < 7))
      (
        key: 'trial:${i.id}:${i.trialEnd!.toIso8601String()}',
        logo: i.merchant,
        color: kAmber,
        title: '${i.merchant} trial ends ${dueLabel(i.trialEnd!).toLowerCase()}',
        sub: i.postTrialAmount == null ? 'Charge after the trial is unknown' : 'Then ${priceTag(i.postTrialAmount!, i.currency, i.cycle)}',
      ),
    for (final i in items.where((i) => !i.isTrial && i.type != 'income' && i.dueAt!.difference(now).inHours < 24))
      (
        key: 'due:${i.id}:${i.dueAt!.toIso8601String()}',
        logo: i.merchant,
        color: kAccent,
        title: '${i.merchant} takes ${money(i.chargeAmount, i.currency)} ${dueLabel(i.dueAt!).toLowerCase()}',
        sub: banks[i.sourceId] ?? 'Payment due',
      ),
  ];
  return all.where((a) => !hidden.contains(a.key)).toList();
});

/// The bell's sheet: only things that need attention, one line each. Swipe or tap × to clear.
class AlertsSheet extends ConsumerWidget {
  const AlertsSheet({super.key, required this.scroll});
  final ScrollController scroll;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    void clear(Iterable<String> keys) {
      final gone = keys.toList(), notifier = ref.read(_dismissedAlerts.notifier);
      notifier.addAll(gone);
      showToast(context, gone.length == 1 ? 'Notification cleared' : '${gone.length} notifications cleared',
          closeSheets: false, onUndo: () => notifier.removeAll(gone));
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Notifications', style: display(20))),
            if (alerts.isNotEmpty) TextButton(onPressed: () => clear(alerts.map((a) => a.key)), child: const Text('Clear all')),
          ]),
        ),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('You\'re all caught up.', style: TextStyle(color: kMuted)),
          ),
        for (final a in alerts)
          Dismissible(
            key: ValueKey(a.key),
            onDismissed: (_) => clear([a.key]),
            background: Container(
              color: kCrimson.withValues(alpha: 0.15),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(CupertinoIcons.trash, color: kCrimson, size: 20),
            ),
            direction: DismissDirection.endToStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(children: [
                MerchantAvatar(a.logo, size: 40, dot: a.color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    Text(a.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                  ]),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(CupertinoIcons.xmark, size: 16, color: kMuted),
                  onPressed: () => clear([a.key]),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

/// 14-day strip: each day shows its charges as provider-coloured dots and the day total.
class _NextDays extends ConsumerWidget {
  const _NextDays({required this.items, required this.base});
  final List<FinancialItem> items;
  final String base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = {for (final s in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) s.id: s.color};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final charges = chargesBetween(items, today, today.add(const Duration(days: 14)));
    final total = charges.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);

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
            final spend = onDay.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);
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
  const _TrialRings(this.trials, this.base);
  final List<FinancialItem> trials;
  final String base;

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
                onTap: () => showSheet(context, Padding(padding: const EdgeInsets.only(bottom: 8), child: ItemRow(t, initiallyOpen: true, pinned: true))),
                padding: const EdgeInsets.all(16),
                border: urgent ? kCrimson.withValues(alpha: 0.35) : null,
                child: SizedBox(
                  width: 168,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Ring fills as the trial runs out, around the brand's logo.
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
      ).fadeRise(ms: 400, rise: 0.05);
}

// ───────── Add ─────────

Future<void> scanReceipt(BuildContext context) async {
  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
  if (img == null || !context.mounted) return;
  showToast(context, 'Reading receipt…', icon: CupertinoIcons.sparkles, tone: kAccent, duration: const Duration(seconds: 20));
  try {
    final res = await parseReceipt({'image_base64': base64Encode(await img.readAsBytes()), 'media_type': img.mimeType ?? 'image/jpeg'});
    if (!context.mounted) return;
    final item = res['item'], dup = res['duplicate'];
    if (item != null) {
      showToast(context, 'Added ${item['merchant_name']}');
    } else if (dup != null) {
      showToast(context, 'You\'re already tracking ${dup['merchant_name']}', icon: CupertinoIcons.info_circle, tone: kAmber);
    } else {
      showToast(context, 'No trial or subscription found in that image', icon: CupertinoIcons.info_circle, tone: kAmber);
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t read that receipt. Try a clearer photo.', e);
  }
}

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
            const Icon(CupertinoIcons.chevron_right, color: kFaint),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 16), child: Text('Add', style: display(24))),
        option(CupertinoIcons.doc_text_viewfinder, kAccent, 'Scan a receipt', 'Picks up the trial end date and price', () {
          // The sheet's context dies on pop; continue from the navigator's.
          final nav = Navigator.of(context)..pop();
          scanReceipt(nav.context);
        }),
        const SizedBox(height: 10),
        option(CupertinoIcons.pencil, const Color(0xFF3D7BFF), 'Add manually', 'Subscription, trial, pay later or income', () {
          final nav = Navigator.of(context)..pop();
          showSheet(nav.context, const ManualItemForm());
        }),
        const SizedBox(height: 10),
        option(FontAwesomeIcons.envelope.data, kMint, 'Forward emails', 'Trials, subscriptions and pay later', () {
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          router.push('/forwarding');
        }),
      ]),
    );
  }
}
