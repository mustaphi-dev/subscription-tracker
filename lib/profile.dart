import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'data.dart';
import 'home.dart';
import 'lock.dart';
import 'ui.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
  bool? _bio;
  String? _inbound;

  @override
  void initState() {
    super.initState();
    PinStore.biometricEnabled().then((v) => mounted ? setState(() => _bio = v) : null);
    db.from('profiles').select('inbound_parse_email').single().then((r) => mounted ? setState(() => _inbound = r['inbound_parse_email']) : null);
  }

  @override
  Widget build(BuildContext context) {
    final user = db.auth.currentUser;
    final base = ref.watch(baseCurrencyProvider).value ?? 'GBP';
    final sources = ref.watch(sourcesProvider).value ?? [];
    final items = (ref.watch(itemsProvider).value ?? []).where((i) => i.status == 'active').toList();
    final trials = items.where((i) => i.isTrial).length;

    // One neutral icon style for every row; colour is reserved for state (the switch) and danger (sign out).
    Widget row(IconData icon, String title, {String? sub, Widget? trailing, VoidCallback? onTap}) => Pressable(
          scale: 0.99,
          onTap: onTap ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 19, color: kText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                ]),
              ),
              trailing ?? (onTap == null ? const SizedBox() : const Icon(Icons.chevron_right_rounded, color: kFaint)),
            ]),
          ),
        );
    Widget group(List<Widget> rows, {String? footer}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Surface(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var k = 0; k < rows.length; k++) ...[if (k > 0) const Divider(height: 1, indent: 66, color: kLine), rows[k]],
              ]),
            ),
            if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(footer, style: caption)),
          ]),
        );
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [Text(value, style: display(20)), Text(label, style: caption)]),
        );
    const statDivider = SizedBox(height: 28, child: VerticalDivider(width: 1, color: kLine));

    return Scaffold(
      body: Ambient(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 24, 0),
                  child: Row(children: [
                    IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => context.pop()),
                    Text('Profile', style: display(20)),
                  ]),
                ),
              ),
            ),
            // Identity and counts in one card instead of a floating avatar plus three loose boxes.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Surface(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Row(children: [
                      const ProfileAvatar(size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(user?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          if (user != null) Text('Member since ${DateFormat('MMMM y').format(DateTime.parse(user.createdAt))}', style: caption),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: kLine),
                    const SizedBox(height: 14),
                    Row(children: [
                      stat('${sources.length}', 'Accounts'),
                      statDivider,
                      stat('${items.length}', 'Tracking'),
                      statDivider,
                      stat('$trials', 'Trials'),
                    ]),
                  ]),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SectionHeader('General')),
            SliverToBoxAdapter(
              child: group([
                row(Icons.currency_exchange_rounded, 'Display currency',
                    sub: currencies.where((c) => c.$1 == base).firstOrNull?.$3 ?? base,
                    trailing: CurrencyPill(current: base, onChanged: setBaseCurrency)),
                row(Icons.account_balance_rounded, 'Manage accounts', sub: '${sources.length} connected or manual', onTap: () {
                  ref.read(tabProvider.notifier).set(2);
                  context.pop();
                }),
              ]),
            ),
            const SliverToBoxAdapter(child: SectionHeader('Security')),
            SliverToBoxAdapter(
              child: group(footer: 'The app locks ${lockTimeout.inSeconds} seconds after you leave it.', [
                row(Icons.face_unlock_rounded, 'Unlock with Face ID',
                    sub: 'Falls back to your 6-digit PIN',
                    trailing: Switch(
                      value: _bio ?? true,
                      onChanged: (v) async {
                        HapticFeedback.selectionClick();
                        setState(() => _bio = v);
                        await PinStore.setBiometric(v);
                        await db.from('profiles').update({'biometric_enabled': v}).eq('id', user!.id);
                      },
                    )),
                row(Icons.pin_rounded, 'Change PIN', onTap: _changePin),
              ]),
            ),
            const SliverToBoxAdapter(child: SectionHeader('Trial emails')),
            SliverToBoxAdapter(child: _ForwardingCard(_inbound)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: kCrimson, minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await db.auth.signOut();
                  },
                  child: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Verify the current PIN (or Face ID) first, then swap in the new-PIN screen.
  void _changePin() => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => LiquidGlassLockScreen(
          title: 'Enter current PIN',
          onCancel: () => Navigator.of(ctx).pop(),
          onDone: () => Navigator.of(ctx).pushReplacement(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx2) => LiquidGlassLockScreen(
              setup: true,
              onCancel: () => Navigator.of(ctx2).pop(),
              onDone: () {
                Navigator.of(ctx2).pop();
                showToast(context, 'PIN updated');
              },
            ),
          )),
        ),
      ));
}

/// The forwarding address is long and meant to be copied, so it gets its own block instead of a truncated row.
class _ForwardingCard extends StatelessWidget {
  const _ForwardingCard(this.address);
  final String? address;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Forward sign-up emails here', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            const Text('We\'ll add the trial or subscription for you.', style: caption),
            const SizedBox(height: 12),
            Pressable(
              onTap: address == null
                  ? () {}
                  : () {
                      Clipboard.setData(ClipboardData(text: address!));
                      showToast(context, 'Forwarding address copied');
                    },
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(child: Text(address ?? '…', maxLines: 2, style: const TextStyle(fontSize: 13, color: kText, fontFeatures: tabular))),
                  const SizedBox(width: 10),
                  const Icon(Icons.copy_rounded, size: 18, color: kMuted),
                ]),
              ),
            ),
          ]),
        ),
      );
}
