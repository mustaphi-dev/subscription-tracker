import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wince/ui.dart';

void main() {
  testWidgets('showToast works from the navigator\'s own context', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
    showToast(nav.currentContext!, 'PIN updated');
    await tester.pump();
    expect(find.text('PIN updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // let the toast close
  });
}
