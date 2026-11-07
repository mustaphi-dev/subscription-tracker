import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avatars.dart';
import 'country.dart';
import 'currency.dart';
import 'data.dart';
import 'export.dart';
import 'legal.dart';
import 'lock.dart';
import 'ui.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = db.auth.currentUser;
    final base = ref.watch(baseProvider);
    final country = ref.watch(profileProvider).value?.country;
    final name = user?.userMetadata?['full_name'] as String?;

    // Tall, borderless, translucent rows packed tight; the page gradient shows through them.
    Widget row(IconData icon, String title, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Pressable(
            scale: 0.98,
            onTap: onTap,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(icon, size: 24, color: kText),
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
                const Icon(CupertinoIcons.chevron_right, size: 16, color: kText),
              ]),
            ),
          ),
        );
    const gap = SizedBox(height: 18);

    return Scaffold(
      backgroundColor: kBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.45, 0.9],
            colors: [kGlow, Color(0xFF241A6E), kBg],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(alignment: Alignment.centerLeft, child: GlassBackButton()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 30),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(22)),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
                      child: const ProfileAvatar(size: 84),
                    ),
                    const SizedBox(height: 16),
                    if (name != null && name.isNotEmpty) ...[
                      Text(name, style: display(24, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                    ] else
                      Text(user?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(20, weight: FontWeight.w600)),
                    if (user != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('Member since ${DateFormat('MMMM y').format(DateTime.parse(user.createdAt))}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ]),
                ),
              ),
              row(CupertinoIcons.arrow_right_arrow_left_circle, 'Currency', () async {
                final picked = await pickFromSheet(context,
                    title: 'Display currency',
                    selected: base,
                    options: [for (final (code, flag, name) in currencyChoices(base)) (code, '$flag  $code', name)]);
                if (picked != null && picked != base) setBaseCurrency(picked);
              }),
              row(CupertinoIcons.globe, 'Country',
                  () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CountryScreen(current: country ?? '')))),
              row(CupertinoIcons.envelope, 'Email forwarding', () => context.push('/forwarding')),
              row(CupertinoIcons.lock, 'Security', () => showSheet(context, const _Security())),
              gap,
              row(FontAwesomeIcons.shareFromSquare.data, 'Export data', () => showSheet(context, const ExportSheet())),
              gap,
              row(CupertinoIcons.chat_bubble, 'Support', () => launchUrl(Uri.parse('mailto:$kSupportEmail?subject=Wince%20support'))),
              row(CupertinoIcons.info, 'About', () => showSheet(context, const _About())),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: kCrimson, minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await signOut();
                  },
                  child: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Face ID and the PIN, in one sheet so the profile stays a plain list.
class _Security extends StatefulWidget {
  const _Security();
  @override
  State<_Security> createState() => _SecurityState();
}

class _SecurityState extends State<_Security> {
  bool? _bio;

  @override
  void initState() {
    super.initState();
    PinStore.biometricEnabled().then((v) => mounted ? setState(() => _bio = v) : null);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Security', style: display(22)),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(children: [
              const Expanded(child: Text('Unlock with Face ID', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
              Switch(
                value: _bio ?? true,
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  setState(() => _bio = v);
                  await PinStore.setBiometric(v);
                },
              ),
            ]),
          ),
          const Divider(height: 1, color: kLine),
          Pressable(
            scale: 0.99,
            onTap: () => changePin(closeSheet(context)),
            child: const SizedBox(
              height: 56,
              child: Row(children: [
                Expanded(child: Text('Change PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
                Icon(CupertinoIcons.chevron_right, size: 16, color: kFaint),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('The app locks ${lockTimeout.inMinutes} minutes after you leave it.', style: caption),
        ]),
      );
}

/// The app, in one sheet: what it is, and where the legal pages live.
class _About extends StatelessWidget {
  const _About();
  @override
  Widget build(BuildContext context) {
    Widget link(String title, VoidCallback onTap) => Pressable(
          scale: 0.99,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
              const Icon(CupertinoIcons.arrow_up_right, size: 16, color: kFaint),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/brand/icon_dark.webp', width: 64, height: 64)),
        const SizedBox(height: 14),
        Text('Wince', style: display(24)),
        const SizedBox(height: 6),
        const Text('Catch trials and renewals before they catch you.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
        const SizedBox(height: 20),
        const Divider(height: 1, color: kLine),
        link('Privacy Policy', () => openLegal(kPrivacyUrl)),
        const Divider(height: 1, color: kLine),
        link('Terms of Service', () => openLegal(kTermsUrl)),
      ]),
    );
  }
}
