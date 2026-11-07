import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'item_tile.dart';
import 'ui.dart';

/// Which Upcoming group [due] falls in, by calendar day like the row labels.
String dueGroup(DateTime? due, [DateTime? now]) {
  if (due == null) return 'Later';
  final n = now ?? DateTime.now();
  final days = daysUntil(due, n);
  if (days < 1) return 'Next 24 hours';
  if (days < 7) return 'This week';
  return due.isBefore(DateTime(n.year, n.month + 1, 1)) ? 'Later this month' : 'Later';
}

/// Upcoming charges grouped by when they're due. With [limit], shows only the soonest few plus a "See all" link.
/// [controls] replaces the type tabs, e.g. with the full page's search and filter; [sheet] opens rows in a sheet.
List<Widget> upcomingSlivers(BuildContext context, WidgetRef ref, List<FinancialItem> items,
    {int? limit, Widget? controls, bool sheet = false}) {
  final total = items.length;
  if (limit != null && total > limit) items = items.take(limit).toList(); // already sorted soonest first
  final groups = <String, List<FinancialItem>>{'Next 24 hours': [], 'This week': [], 'Later this month': [], 'Later': []};
  for (final i in items) {
    groups[dueGroup(i.dueAt)]!.add(i);
  }
  final filter = ref.watch(typeFilterProvider);
  return [
    if (limit != null) const SliverToBoxAdapter(child: SectionHeader('Upcoming')),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: controls ??
            Segmented(
              labels: [for (final t in typeFilters) _filterLabel(t)],
              selected: typeFilters.indexOf(filter),
              onSelect: (k) => ref.read(typeFilterProvider.notifier).set(typeFilters[k]),
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
              money(e.value.where((i) => i.type != 'income').fold(0.0, (s, i) => s + (i.baseAmount ?? 0)), ref.watch(baseProvider)),
              style: const TextStyle(color: kMuted, fontSize: 12, fontFeatures: tabular),
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(child: ItemGroup(e.value, sheet: sheet).fadeRise()),
    ],
    if (limit != null && total > limit)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: OutlinedButton(onPressed: () => context.push('/upcoming'), child: Text('See all $total')),
        ),
      ),
  ];
}

String _filterLabel(String? type) => type == null ? 'All' : itemTypes[type]!.tab;

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
        label: 'Filter: ${_filterLabel(type)}',
        child: Pressable(
          onTap: () async {
            // The sheet returns null when dismissed, so "All" is picked by its index.
            final picked = await pickFromSheet<int>(
              context,
              title: 'Show',
              options: [for (final (k, t) in typeFilters.indexed) (k, _filterLabel(t), null)],
              selected: typeFilters.indexOf(type),
            );
            if (picked != null) ref.read(typeFilterProvider.notifier).set(typeFilters[picked]);
          },
          child: Glass(
            radius: 24,
            tint: type == null ? const Color(0x1AFFFFFF) : kAccent.withValues(alpha: 0.25),
            child: Container(
              height: 48,
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.slider_horizontal_3, size: 18),
                if (type != null) ...[
                  const SizedBox(width: 6),
                  Text(_filterLabel(type), style: const TextStyle(fontWeight: FontWeight.w600)),
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
            ...upcomingSlivers(context, ref, items, controls: controls, sheet: true),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}
