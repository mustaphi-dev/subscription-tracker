import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

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

class _CalendarState extends ConsumerState<TrialsCalendarTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _day = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final items = ref.watch(itemsProvider).value ?? [];
    final sources = {for (final s in ref.watch(sourcesProvider).value ?? <PaymentSource>[]) s.id: s.provider};
    final charges = chargesBetween(items, _month, DateTime(_month.year, _month.month + 1));
    final monthOut = charges.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount);
    final onDay = charges.where((c) => DateUtils.isSameDay(c.date, _day)).toList();
    final trials = items.where((i) => i.isTrial && i.status != 'cancelled' && i.trialEnd != null && i.trialEnd!.isAfter(DateTime.now())).toList();

    final firstWeekday = _month.weekday; // Mon = 1
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final today = DateUtils.dateOnly(DateTime.now());

    return TabPage(
      title: 'Calendar',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DateFormat('MMMM').format(_month), style: display(34)),
                  Text('${money(monthOut, base)} due this month', style: const TextStyle(color: kMuted, fontFeatures: tabular)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Surface(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: Column(children: [
                Row(children: [
                  for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(child: Center(child: Text(d, style: const TextStyle(color: kFaint, fontSize: 12, fontWeight: FontWeight.w600)))),
                ]),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.82,
                  children: [
                    for (var k = 1; k < firstWeekday; k++) const SizedBox(),
                    for (var d = 1; d <= days; d++)
                      Builder(builder: (_) {
                        final date = DateTime(_month.year, _month.month, d);
                        final cs = charges.where((c) => DateUtils.isSameDay(c.date, date)).toList();
                        final selected = DateUtils.isSameDay(date, _day);
                        final isToday = DateUtils.isSameDay(date, today);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _day = date);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: selected ? kText : (cs.isNotEmpty ? kSurfaceHi : Colors.transparent),
                              borderRadius: BorderRadius.circular(12),
                              border: isToday && !selected ? Border.all(color: kAccent) : null,
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('$d', style: TextStyle(fontWeight: FontWeight.w600, color: selected ? kBg : (date.isBefore(today) ? kFaint : kText))),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 5,
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  for (final c in cs.take(3))
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.symmetric(horizontal: 1),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c.amount > 0 ? kMint : c.item.isTrial ? kAccent : (providerColors[sources[c.item.sourceId]] ?? kMuted),
                                      ),
                                    ),
                                ]),
                              ),
                            ]),
                          ),
                        );
                      }),
                  ],
                ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            DateUtils.isSameDay(_day, today) ? 'Today' : DateFormat('EEEE d MMMM').format(_day),
            trailing: onDay.isEmpty
                ? null
                : Text(money(onDay.where((c) => c.amount < 0).fold(0.0, (s, c) => s - c.amount), base),
                    style: const TextStyle(color: kMuted, fontFeatures: tabular)),
          ),
        ),
        SliverToBoxAdapter(
          child: onDay.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Nothing due on this day.', style: TextStyle(color: kMuted)),
                )
              : ItemGroup(onDay.map((c) => c.item).toList()),
        ),
        if (trials.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader('Active trials', trailing: Text('${trials.length}', style: label))),
          SliverToBoxAdapter(child: ItemGroup(trials)),
        ],
      ],
    );
  }
}

// ───────── Accounts ─────────

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final total = sources.fold(0.0, (s, a) => s + (a.baseBalance ?? 0));
    final connected = sources.map((s) => s.provider).toSet();

    return TabPage(
      title: 'Accounts',
      onRefresh: () async {
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Accounts', style: display(34)),
              const SizedBox(height: 14),
              const Text('Across all accounts', style: label),
              BigMoney(total, base, size: 40),
            ]),
          ),
        ),
        if (sources.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Connected')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Surface(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var k = 0; k < sources.length; k++) ...[
                    if (k > 0) const Divider(height: 1, indent: 70, color: kLine),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        _ProviderMark(sources[k].provider),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(sources[k].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              sources[k].lastSynced == null
                                  ? providerLabels[sources[k].provider]!
                                  : 'Synced ${DateFormat('d MMM, HH:mm').format(sources[k].lastSynced!)}',
                              style: caption,
                            ),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money(sources[k].balance, sources[k].currency), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                          if (sources[k].currency != base && sources[k].baseBalance != null)
                            Text('≈ ${money(sources[k].baseBalance!, base)}', style: caption),
                        ]),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SectionHeader('Add an account')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                for (final p in providerLabels.keys)
                  Surface(
                    onTap: () async {
                      try {
                        await launchUrl(Uri.parse(await connectBank(p)), mode: LaunchMode.externalApplication);
                      } catch (e) {
                        if (context.mounted) showError(context, 'Couldn\'t connect ${providerLabels[p]}: ${functionError(e)}');
                      }
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        _ProviderMark(p, size: 32),
                        const Spacer(),
                        Icon(connected.contains(p) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            color: connected.contains(p) ? kMint : kMuted, size: 20),
                      ]),
                      const Spacer(),
                      Text(providerLabels[p]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(connected.contains(p) ? 'Add another' : 'Open Banking', style: caption),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader('Security')),
        const SliverToBoxAdapter(child: _SecuritySettings()),
      ],
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark(this.provider, {this.size = 40});
  final String provider;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = providerColors[provider] ?? kAccent;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(providerLabels[provider]![0], style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
    );
  }
}

class _SecuritySettings extends StatefulWidget {
  const _SecuritySettings();
  @override
  State<_SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<_SecuritySettings> {
  bool? _bio;
  @override
  void initState() {
    super.initState();
    PinStore.biometricEnabled().then((v) => setState(() => _bio = v));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unlock with Face ID'),
              activeTrackColor: kMint,
              value: _bio ?? true,
              onChanged: (v) async {
                await PinStore.setBiometric(v);
                await db.from('profiles').update({'biometric_enabled': v}).eq('id', db.auth.currentUser!.id);
                setState(() => _bio = v);
              },
            ),
            const Divider(height: 1, color: kLine),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sign out', style: TextStyle(color: kCrimson)),
              onTap: () => db.auth.signOut(),
            ),
          ]),
        ),
      );
}

// ───────── Sheets ─────────

class AlertsSheet extends ConsumerWidget {
  const AlertsSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final soon = chargesBetween(ref.watch(itemsProvider).value ?? [], now, now.add(const Duration(days: 7)));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Text('Next 7 days', style: display(22))),
      if (soon.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text('Nothing due. We\'ll notify you 7 days, 3 days and 24 hours before any trial converts.',
              style: TextStyle(color: kMuted, height: 1.4)),
        )
      else
        Flexible(child: SingleChildScrollView(child: ItemGroup(soon.map((c) => c.item).toSet().toList()))),
      const SizedBox(height: 16),
    ]);
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
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: kMint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.alternate_email_rounded, color: kMint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Forward trial emails', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(email ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                ]),
              ),
              const Icon(Icons.copy_rounded, size: 18, color: kFaint),
            ]),
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
        if (_type == 'installment') ...{
          'installment_total_count': installments,
          'installment_remaining_balance': amount * (installments ?? 0),
        },
      });
    } catch (e) {
      if (mounted) showError(context, 'Couldn\'t save: $e');
      return;
    }
    if (!mounted) return;
    final nav = Navigator.of(context)..pop();
    showToast(nav.context, 'Added ${_merchant.text.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    Widget field(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: caption),
            const SizedBox(height: 6),
            child,
          ]),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 16), child: Text('New item', style: display(24))),
        Segmented(
          labels: const ['Subscription', 'Trial', 'Pay later', 'Income'],
          selected: _types.indexOf(_type),
          onSelect: (i) => setState(() => _type = _types[i]),
        ),
        const SizedBox(height: 16),
        field('Name', TextField(controller: _merchant, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. Netflix'))),
        field(
          switch (_type) { 'free_trial' => 'Charge after the trial', 'installment' => 'Each payment', 'income' => 'Amount received', _ => 'Amount' },
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontFeatures: tabular),
                decoration: const InputDecoration(hintText: '0.00'),
              ),
            ),
            const SizedBox(width: 8),
            box(DropdownButton<String>(
              value: _currency,
              underline: const SizedBox(),
              dropdownColor: kSurfaceHi,
              items: [for (final c in ['GBP', 'USD', 'EUR', 'GHS']) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _currency = v!),
            )),
          ]),
        ),
        if (_type == 'installment') field('Number of payments', TextField(controller: _installTotal, keyboardType: TextInputType.number)),
        Row(children: [
          Expanded(
            child: field(
              'Repeats',
              box(DropdownButton<String>(
                isExpanded: true,
                value: _cycle,
                underline: const SizedBox(),
                dropdownColor: kSurfaceHi,
                items: [
                  for (final c in ['weekly', 'monthly', 'quarterly', 'yearly', 'once'])
                    DropdownMenuItem(value: c, child: Text('${c[0].toUpperCase()}${c.substring(1)}')),
                ],
                onChanged: (v) => setState(() => _cycle = v!),
              )),
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
        ]),
        field(
          _type == 'income' ? 'Paid into' : 'Paid from',
          box(DropdownButton<String?>(
            isExpanded: true,
            value: _sourceId,
            hint: Text(sources.isEmpty ? 'No accounts connected' : 'Choose an account', style: const TextStyle(color: kMuted)),
            underline: const SizedBox(),
            dropdownColor: kSurfaceHi,
            items: [for (final s in sources) DropdownMenuItem(value: s.id, child: Text('${providerLabels[s.provider]} · ${s.name}'))],
            onChanged: (v) => setState(() => _sourceId = v),
          )),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ]),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.go('/'))),
            Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), child: Text('Is this a free trial?', style: display(28))),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Text('We spotted a card check from this merchant. Confirm it so we can warn you before it starts charging.',
                  style: TextStyle(color: kMuted, height: 1.4)),
            ),
            if (item == null) const Center(child: CircularProgressIndicator()) else ItemGroup([item]),
          ]),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(flex: 2),
                const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 56)),
                const SizedBox(height: 28),
                Text('Every renewal,\nbefore it hits.', style: display(38)),
                const SizedBox(height: 12),
                const Text('Subscriptions, free trials, Pay in 3 and balances across Revolut, Wise, Lloyds and PayPal.',
                    style: TextStyle(color: kMuted, height: 1.4)),
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
                          child: Text(
                            _error ?? 'Check your inbox and tap "Sign in" on this phone.',
                            style: TextStyle(color: _error == null ? kMint : kCrimson),
                          ),
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
              ]),
            ),
          ),
        ),
      );
}
