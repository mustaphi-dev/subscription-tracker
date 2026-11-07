import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'alerts.dart';
import 'avatars.dart';
import 'currency.dart';
import 'data.dart';
import 'ui.dart';

/// The bottom bar's tabs, in order.
enum AppTab {
  home(CupertinoIcons.house, 'Home'),
  calendar(CupertinoIcons.calendar, 'Calendar'),
  accounts(CupertinoIcons.creditcard, 'Accounts'),
  insights(CupertinoIcons.chart_bar, 'Insights');

  const AppTab(this.icon, this.label);
  final IconData icon;
  final String label;
}

final tabProvider = NotifierProvider<Pick<AppTab>, AppTab>(() => Pick(AppTab.home));

/// True once the current tab is scrolled away from the top: the bottom bar shrinks and drops its labels.
final navCompactProvider = NotifierProvider<Pick<bool>, bool>(() => Pick(false));

/// Switches tab with the bar open, as tapping it does.
void goToTab(WidgetRef ref, AppTab tab) {
  ref.read(navCompactProvider.notifier).set(false);
  ref.read(tabProvider.notifier).set(tab);
}

/// Height of [TopBar] below the status bar.
const kTopBarHeight = 56.0;

/// Space left under a tab's content so the floating nav doesn't cover the end of it.
const kNavClearance = 140.0;

/// Pinned top bar that turns into glass only once content scrolls underneath it.
class TopBar extends ConsumerWidget {
  const TopBar({super.key, required this.scrolled, this.title});
  final bool scrolled;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseProvider);
    final alert = ref.watch(alertsProvider).isNotEmpty;
    final bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: kTopBarHeight,
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.55, 1],
                  colors: [kBg, kBg.withAlpha(0xE6), kBg.withAlpha(0)],
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
  const TabPage({super.key, required this.slivers, this.title, this.onRefresh, this.pad = true});
  final List<Widget> slivers;
  final String? title;
  final Future<void> Function()? onRefresh;

  /// False when the slivers clear the top bar and the nav themselves (the calendar's pinned
  /// header and its sheet that runs to the bottom of the screen).
  final bool pad;
  @override
  ConsumerState<TabPage> createState() => _TabPageState();
}

class _TabPageState extends ConsumerState<TabPage> {
  bool _scrolled = false;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + kTopBarHeight;
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
          if (widget.pad) SliverToBoxAdapter(child: SizedBox(height: top)),
          ...widget.slivers,
          if (widget.pad) const SliverToBoxAdapter(child: SizedBox(height: kNavClearance)),
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
