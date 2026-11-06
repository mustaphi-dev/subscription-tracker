import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/countries.dart';

void main() {
  test('every country has a unique code, a flag and a known currency', () {
    expect(countries.length, greaterThan(240));
    expect(countries.map((c) => c.code).toSet().length, countries.length);
    for (final c in countries) {
      expect(c.currency, matches(RegExp(r'^[A-Z]{3}$')), reason: c.code);
      expect(c.flag, isNotEmpty, reason: c.code);
    }
  });

  test('currency map covers the whole list, so nothing silently falls back to USD', () {
    const usdCountries = {'US', 'AS', 'BQ', 'EC', 'FM', 'GU', 'IO', 'MH', 'MP', 'PR', 'PW', 'SV', 'TC', 'TL', 'VG', 'VI'};
    final fellBack = [for (final c in countries) if (c.currency == 'USD' && !usdCountries.contains(c.code)) c.code];
    expect(fellBack, isEmpty);
  });

  test('lookup, flag, dial code and currency', () {
    final gb = countryByCode('gb')!;
    expect(gb.flag, '🇬🇧');
    expect(gb.dialCode, '44');
    expect(gb.currency, 'GBP');
    expect(countryByCode('GH')!.currency, 'GHS');
    expect(countryByCode('ZZ'), isNull);
  });

  test('bank linking starts with the UK only', () {
    expect(countryByCode('GB')!.bankLinking, isTrue);
    expect(countryByCode('GH')!.bankLinking, isFalse);
  });
}
