import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import 'brands.dart';
import 'data.dart';
import 'home.dart';
import 'item_tile.dart';
import 'lock.dart';
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
                        : ItemGroup(onDay.map((c) => c.item).toList(), color: Color.lerp(kSurface, kSurfaceHi, f)!),
                    if (trials.isNotEmpty) ...[
                      SectionHeader('Active trials', trailing: Text('${trials.length}', style: label)),
                      ItemGroup(trials, color: Color.lerp(kSurface, kSurfaceHi, f)!),
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

    return TabPage(
      title: 'Accounts',
      onRefresh: () async {
        if (!sources.any((s) => !s.isManual)) return;
        try {
          await syncBanks();
        } catch (e) {
          if (context.mounted) showError(context, 'Sync failed: ${functionError(e)}');
        }
      },
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accounts', style: display(34)),
                const SizedBox(height: 14),
                Text('Across ${sources.length} account${sources.length == 1 ? '' : 's'}', style: label),
                BigMoney(total, base, size: 40),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader('Your accounts')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: sources.isEmpty
                ? Surface(
                    onTap: () => showSheet(context, const AccountForm()),
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
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                          child: const Icon(CupertinoIcons.plus, color: Colors.white, size: 22),
                        ),
                      ],
                    ),
                  )
                : Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var k = 0; k < sources.length; k++) ...[
                          if (k > 0) const Divider(height: 1, indent: 70, color: kLine),
                          _AccountRow(sources[k], base),
                        ],
                        // The one place to add a manual account once you have some.
                        const Divider(height: 1, indent: 70, color: kLine),
                        Pressable(
                          scale: 0.99,
                          onTap: () => showSheet(context, const AccountForm()),
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                SizedBox.square(dimension: 40, child: Icon(CupertinoIcons.plus, color: kMuted)),
                                SizedBox(width: 14),
                                Text(
                                  'Add account',
                                  style: TextStyle(color: kMuted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader('Connect automatically')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Surface(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Open Banking keeps balances and renewals in sync without typing them in.',
                    style: TextStyle(color: kMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final p in providerLabels.keys)
                        Expanded(
                          child: Pressable(
                            onTap: () async {
                              try {
                                await launchUrl(Uri.parse(await connectBank(p)), mode: LaunchMode.externalApplication);
                              } catch (e) {
                                if (context.mounted) showError(context, 'Couldn\'t connect ${providerLabels[p]}: ${functionError(e)}');
                              }
                            },
                            child: Column(
                              children: [
                                _BankMark(providerLabels[p]!, providerColors[p]!, size: 44),
                                const SizedBox(height: 6),
                                Text(providerLabels[p]!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow(this.s, this.base);
  final PaymentSource s;
  final String base;
  @override
  Widget build(BuildContext context) => Pressable(
    scale: 0.99,
    onTap: () => showSheet(context, AccountForm(account: s)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _BankMark(s.bank, s.color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name == s.bank ? s.bank : '${s.bank} · ${s.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  s.isManual
                      ? 'Manual · updated ${s.lastSynced == null ? 'never' : DateFormat('d MMM').format(s.lastSynced!)}'
                      : 'Open Banking · synced ${s.lastSynced == null ? 'never' : DateFormat('d MMM, HH:mm').format(s.lastSynced!)}',
                  style: caption,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(s.balance, s.currency),
                style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
              ),
              if (s.currency != base && s.baseBalance != null) Text('≈ ${money(s.baseBalance!, base)}', style: caption),
            ],
          ),
        ],
      ),
    ),
  );
}

class _BankMark extends StatelessWidget {
  const _BankMark(this.name, this.color, {super.key, this.size = 40});
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

const _currencies = ['GBP', 'USD', 'EUR', 'GHS', 'NGN', 'KES', 'ZAR', 'CAD', 'AUD', 'CHF', 'JPY', 'INR', 'AED'];
const _bankSuggestions = [
  'Revolut',
  'Wise',
  'Lloyds',
  'PayPal',
  'Monzo',
  'Starling',
  'Barclays',
  'HSBC',
  'NatWest',
  'Santander',
  'Halifax',
  'Nationwide',
  'Chase UK',
  'Amex',
];

/// Add or edit a manually tracked account (any bank, card or wallet).
class AccountForm extends StatefulWidget {
  const AccountForm({super.key, this.account});
  final PaymentSource? account;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  late final _bank = TextEditingController(text: widget.account?.bank ?? '');
  late final _name = TextEditingController(text: widget.account == null || widget.account!.name == widget.account!.bank ? '' : widget.account!.name);
  late final _balance = TextEditingController(text: widget.account?.balance.toStringAsFixed(2) ?? '');
  late String _currency = widget.account?.currency ?? 'GBP';
  bool _confirmDelete = false, _busy = false;

  bool get _editing => widget.account != null;
  bool get _linked => widget.account != null && !widget.account!.isManual;

  Future<void> _save() async {
    final balance = double.tryParse(_balance.text.replaceAll(',', ''));
    if (_bank.text.trim().isEmpty || balance == null) {
      showError(context, 'Add the bank name and current balance');
      return;
    }
    setState(() => _busy = true);
    try {
      await saveAccount(id: widget.account?.id, bank: _bank.text, name: _name.text, currency: _currency, balance: balance);
      if (mounted) showToast(context, _editing ? 'Account updated' : 'Added ${_bank.text.trim()}');
    } catch (e) {
      if (mounted) showError(context, 'Couldn\'t save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!_confirmDelete) {
      HapticFeedback.mediumImpact();
      setState(() => _confirmDelete = true);
      return;
    }
    await deleteAccount(widget.account!.id);
    if (mounted) showToast(context, 'Account removed');
  }

  @override
  Widget build(BuildContext context) {
    final preview = PaymentSource({
      'id': '',
      'provider': knownBanks.contains(_bank.text.trim().toLowerCase()) ? _bank.text.trim().toLowerCase() : 'other',
      'institution': _bank.text.trim(),
      'account_name': _name.text,
      'currency': _currency,
    });
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _BankMark(preview.bank, preview.color, key: ValueKey(preview.bank), size: 44),
                ),
                const SizedBox(width: 12),
                Text(_editing ? 'Edit account' : 'New account', style: display(24)),
              ],
            ),
          ),
          if (_linked)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('This account syncs through Open Banking; manual changes are overwritten on the next sync.', style: caption),
            ),
          const Text('Bank or wallet', style: caption),
          const SizedBox(height: 6),
          TextField(
            controller: _bank,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Monzo'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _bankSuggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Pressable(
                onTap: () => setState(() => _bank.text = _bankSuggestions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kSurfaceHi,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: kLine),
                  ),
                  child: Text(_bankSuggestions[i], style: const TextStyle(fontSize: 12, color: kMuted)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Account nickname (optional)', style: caption),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Current, Savings, Joint…'),
          ),
          const SizedBox(height: 14),
          const Text('Current balance', style: caption),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _balance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: const TextStyle(fontFeatures: tabular),
                  decoration: const InputDecoration(hintText: '0.00'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: SelectField<String>(
                  title: 'Currency',
                  options: currencyOptions(_currencies),
                  value: _currency,
                  onChanged: (v) => setState(() => _currency = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_editing ? 'Save changes' : 'Add account')),
          if (_editing) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _delete,
              child: Text(_confirmDelete ? 'Tap again to remove — its items stay, unassigned' : 'Remove account', style: const TextStyle(color: kCrimson)),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────── Sheets ─────────

class AlertsSheet extends ConsumerWidget {
  const AlertsSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final soon = chargesBetween(ref.watch(itemsProvider).value ?? [], now, now.add(const Duration(days: 7)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text('Next 7 days', style: display(22)),
        ),
        if (soon.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Text('Nothing due. We\'ll notify you 7 days, 3 days and 24 hours before any trial converts.', style: TextStyle(color: kMuted, height: 1.4)),
          )
        else
          Flexible(child: SingleChildScrollView(child: ItemGroup(soon.map((c) => c.item).toSet().toList()))),
        const SizedBox(height: 16),
      ],
    );
  }
}

class InboundEmailTile extends StatelessWidget {
  const InboundEmailTile({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: db.from('profiles').select('inbound_parse_email').single(),
    builder: (_, snap) {
      final email = snap.data?['inbound_parse_email'] as String?;
      return Surface(
        color: kSurfaceHi,
        onTap: email == null
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: email));
                showToast(context, 'Forwarding address copied');
              },
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: kMint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
              child: const Icon(CupertinoIcons.at, color: kMint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Forward trial emails', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(email ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                ],
              ),
            ),
            const Icon(CupertinoIcons.doc_on_doc, size: 18, color: kFaint),
          ],
        ),
      );
    },
  );
}

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
      if (mounted) showError(context, 'Couldn\'t save: $e');
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
              if (item == null) const Center(child: CircularProgressIndicator()) else ItemGroup([item]),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────── Sign in (email magic link → subtracker://login-callback) ─────────

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  final _email = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;

  // supabase_flutter picks up the deep link and completes sign-in; the router then redirects home.
  Future<void> _send() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await db.auth.signInWithOtp(email: _email.text.trim(), emailRedirectTo: 'subtracker://login-callback');
      setState(() => _sent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Ambient(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 56)),
              const SizedBox(height: 28),
              Text('Every renewal,\nbefore it hits.', style: display(38)),
              const SizedBox(height: 12),
              const Text(
                'Subscriptions, free trials, Pay in 3 and balances across Revolut, Wise, Lloyds and PayPal.',
                style: TextStyle(color: kMuted, height: 1.4),
              ),
              const Spacer(flex: 3),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: springOut,
                child: _sent || _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error ?? 'Check your inbox and tap "Sign in" on this phone.', style: TextStyle(color: _error == null ? kMint : kCrimson)),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kBg))
                    : Text(_sent ? 'Resend link' : 'Continue with email'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
