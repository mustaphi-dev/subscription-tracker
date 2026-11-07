import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avatars.dart';
import 'brands.dart';
import 'countries.dart';
import 'data.dart';
import 'tab_page.dart';
import 'ui.dart';

/// Pull to refresh: re-reads linked banks (nothing to do with only manual accounts).
Future<void> refreshBanks(BuildContext context, WidgetRef ref) async {
  if (!(ref.read(sourcesProvider).value ?? []).any((s) => !s.isManual)) return;
  try {
    await syncBanks();
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t refresh your banks. Try again in a moment.', e);
  }
}

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    final base = ref.watch(baseProvider);
    final country = ref.watch(profileProvider).value?.country;

    return TabPage(
      title: 'Accounts',
      onRefresh: () => refreshBanks(context, ref),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total balance', style: TextStyle(color: kMuted, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                BigMoney(sources.totalBase, base, size: 52),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            // The plus searches every bank in your country.
            child: Surface(
              onTap: () {
                final why = _syncUnavailable(country);
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
                    'Tap a bank to link it in seconds.',
                    style: TextStyle(color: kMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final b in banks) _BankTile(b.label, () => _connectByName(context, ref, country, b.label)),
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
    final total = accounts.totalBase;
    return Pressable(
      scale: 0.99,
      onTap: () => showSheet(context, _BankSheet(accounts, base)),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          MerchantAvatar(first.bank, tint: first.color),
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
      final ok = await confirmSheet(
        context,
        title: manual ? 'Remove $bank?' : 'Unlink $bank?',
        body: manual
            ? 'Its balance goes from your total. Subscriptions you track stay, without an account.'
            : 'We\'ll stop reading $bank and remove its ${accounts.length == 1 ? 'account' : '${accounts.length} accounts'} here. '
                'Subscriptions found from it stay. You can connect it again any time.',
        action: manual ? 'Remove' : 'Unlink',
      );
      if (!ok || !context.mounted) return;
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
            MerchantAvatar(bank, size: 44, tint: accounts.first.color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bank, style: display(20)),
                Text(manual ? 'Added manually' : 'Linked', style: caption),
              ]),
            ),
            Text(money(accounts.totalBase, base), style: display(18)),
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

/// Why bank sync can't be used in [code] (the profile's country), or null when it can.
String? _syncUnavailable(String? code) {
  final country = countryByCode(code);
  if (country == null) return 'Set your country in Profile to connect a bank.';
  return country.bankLinking ? null : 'Bank sync isn\'t available in ${country.name} yet.';
}

/// Connects [name] (e.g. "Lloyds") using the provider's own name for it (e.g. "Lloyds Bank").
Future<void> _connectByName(BuildContext context, WidgetRef ref, String? country, String name) async {
  final why = _syncUnavailable(country);
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
  const _BankTile(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Pressable(
      onTap: onTap,
      child: Column(
        children: [
          MerchantAvatar(label, size: 44, tint: bankColor(label)),
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
                      MerchantAvatar(shown[i], size: 36, tint: bankColor(shown[i])),
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
