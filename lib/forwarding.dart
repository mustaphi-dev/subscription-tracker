import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data.dart';
import 'ui.dart';

/// How forwarding works, ending with the address to copy. First-time users don't know
/// what to do with a bare address, so the copy button lives at the end of the steps.
class ForwardingScreen extends ConsumerWidget {
  const ForwardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(inboundAddressProvider).value;
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(alignment: Alignment.centerLeft, child: GlassBackButton()),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    Text('Forward emails', style: display(28)),
                    const SizedBox(height: 8),
                    const Text(
                      'Send us the email you get when you start a trial, subscribe, or buy with pay later. We\'ll add it and remind you before you\'re charged.',
                      style: TextStyle(color: kMuted, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    const _Step(1, 'Open the email', 'The welcome or receipt email, like "Your Netflix trial has started" or a Spotify receipt.'),
                    const _Step(2, 'Tap Forward', 'Works the same in Gmail, Outlook and Apple Mail.'),
                    const _Step(3, 'Send it to your address below', 'Paste it in the To field and send. It shows up here in about a minute.'),
                    const SizedBox(height: 12),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Your address', style: caption),
                          const SizedBox(height: 6),
                          Text(
                            address ?? '…',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: tabular),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: address == null
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: address));
                                    showToast(context, 'Address copied');
                                  },
                            icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                            label: const Text('Copy address'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Only emails sent to this address are read. Keep it to yourself, like a password.', textAlign: TextAlign.center, style: caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.title, this.sub);
  final int n;
  final String title, sub;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: kMint.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Text(
            '$n',
            style: const TextStyle(color: kMint, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );
}
