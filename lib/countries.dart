import 'dart:ui' show PlatformDispatcher;

import 'package:country_picker/country_picker.dart' as cp;

part 'countries_data.dart';

/// A country as the app uses it: country_picker's names, flags and dial codes, plus
/// the local currency and whether bank linking is offered there.
class Country {
  Country._(this._c);
  final cp.Country _c;

  /// ISO 3166-1 alpha-2, e.g. GB.
  String get code => _c.countryCode;
  String get name => _c.name;
  String get flag => _c.flagEmoji;

  /// International dialling code without the plus, e.g. 44.
  String get dialCode => _c.phoneCode;

  /// Main local currency; USD where none is known.
  String get currency => _currencyByCountry[code] ?? 'USD';

  /// Whether automatic bank sync works here. Grows as bank-data providers are added.
  bool get bankLinking => bankLinkingCountries.contains(code);
}

/// Countries where Open Banking account linking is offered. UK first.
const bankLinkingCountries = {'GB'};

/// Every country, in country_picker's alphabetical order (which files Åland under A).
final List<Country> countries = [for (final c in cp.CountryService().getAll()) Country._(c)];

final _byCode = {for (final c in countries) c.code: c};

Country? countryByCode(String? code) => code == null ? null : _byCode[code.toUpperCase()];

/// Best guess from the phone's region setting (e.g. en_GB → United Kingdom).
Country? deviceCountry() {
  for (final l in PlatformDispatcher.instance.locales) {
    final c = countryByCode(l.countryCode);
    if (c != null) return c;
  }
  return null;
}
