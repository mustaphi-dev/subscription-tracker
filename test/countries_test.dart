import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/countries.dart';

void main() {
  test('country codes are unique, upper-case and have a currency', () {
    final codes = countries.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final c in countries) {
      expect(c.code, matches(RegExp(r'^[A-Z]{2}$')));
      expect(c.currency, matches(RegExp(r'^[A-Z]{3}$')));
    }
  });

  test('flag and lookup', () {
    expect(countryByCode('gb')!.flag, '🇬🇧');
    expect(countryByCode('GH')!.currency, 'GHS');
    expect(countryByCode('ZZ'), isNull);
  });

  test('bank linking starts with the UK only', () {
    expect(countryByCode('GB')!.bankLinking, isTrue);
    expect(countryByCode('GH')!.bankLinking, isFalse);
  });
}
