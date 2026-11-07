import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts.dart';
import 'add.dart';
import 'calendar.dart';
import 'home.dart';
import 'insights.dart';
import 'tab_page.dart';
import 'ui.dart';

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
            index: tab.index,
            children: const [DashboardTab(), TrialsCalendarTab(), AccountsTab(), InsightsTab()], // in AppTab order
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
                        onTap: (t) => goToTab(ref, t),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Pressable(
                      onTap: () => showSheet(context, const AddSheet()),
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
  final AppTab tab;
  final ValueChanged<AppTab> onTap;
  final double height;

  /// 1 = labels fully shown, 0 = icons only.
  final double labels;

  @override
  Widget build(BuildContext context) => Glass(
        radius: height / 2,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 12) / AppTab.values.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: springBounce,
                left: 6 + w * tab.index,
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
                  for (final t in AppTab.values)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: t == tab,
                        label: t.label,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(t);
                          },
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(t.icon, size: 22, color: t == tab ? kText : kMuted),
                            // Collapses its own height as well as fading, so the icon re-centres.
                            ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: labels,
                                child: Opacity(
                                  opacity: labels,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(t.label,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: t == tab ? kText : kMuted)),
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
