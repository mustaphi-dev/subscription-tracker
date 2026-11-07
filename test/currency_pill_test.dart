import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wince/ui.dart';

void main() {
  testWidgets('picking a currency reports it', (t) async {
    String? got;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: CurrencyPill(current: 'GBP', onChanged: (c) => got = c)))));
    await t.tap(find.byType(CurrencyPill));
    await t.pumpAndSettle();
    await t.tap(find.text('USD'));
    await t.pumpAndSettle();
    expect(got, 'USD');
  });
}
