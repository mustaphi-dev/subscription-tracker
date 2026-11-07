import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Supabase stores its session through shared_preferences, so the test mocks it.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wince/accounts.dart';
import 'package:wince/data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://localhost', anonKey: 'test');
  });

  testWidgets('bank search keeps every typed letter and filters the list', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sourcesProvider.overrideWith((_) => Stream.value([])),
        profileProvider.overrideWith((_) => Stream.value(Profile({'country': 'GB'}))),
        shortfallProvider.overrideWith((_) async => <Shortfall>[]),
        itemsProvider.overrideWith((_) => Stream.value([])),
        banksProvider.overrideWith((_) async => ['Monzo Bank', 'Revolut', 'Royal Bank of Scotland']),
      ],
      child: const MaterialApp(home: Scaffold(body: AccountsTab())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an account'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, 'r');
    await tester.pump();
    await tester.enterText(field, 're');
    await tester.pump();
    expect(find.text('re'), findsOneWidget);
    expect(find.text('Revolut'), findsWidgets);
    expect(find.text('Monzo Bank'), findsNothing);
  });
}
