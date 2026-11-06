import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/data.dart';
import 'package:subtracker/forwarding.dart';

void main() {
  testWidgets('guide shows the steps and copies the address', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await t.pumpWidget(ProviderScope(
      overrides: [inboundAddressProvider.overrideWith((_) async => 'adams-k7f2x@trywince.app')],
      child: const MaterialApp(home: ForwardingScreen()),
    ));
    await t.pump();
    expect(find.text('Tap Forward'), findsOneWidget);
    expect(find.text('adams-k7f2x@trywince.app'), findsOneWidget);
    await t.tap(find.text('Copy address'));
    await t.pump(const Duration(seconds: 5));
    expect(copied, 'adams-k7f2x@trywince.app');
  });
}
