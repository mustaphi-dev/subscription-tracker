import 'dart:ui' show PlatformDispatcher;

part 'countries_data.dart';

class Country {
  const Country(this.code, this.name, this.currency);
  final String code, name, currency;

  /// Regional-indicator emoji built from the two-letter code.
  String get flag => String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  /// Whether automatic bank sync works here. Grows as bank-data providers are added.
  bool get bankLinking => bankLinkingCountries.contains(code);
}

/// Countries where Open Banking account linking is offered. UK first.
const bankLinkingCountries = {'GB'};

const countries = _all;

Country? countryByCode(String? code) {
  if (code == null) return null;
  final c = code.toUpperCase();
  for (final x in _all) {
    if (x.code == c) return x;
  }
  return null;
}

/// Best guess from the phone's region setting (e.g. en_GB → United Kingdom).
Country? deviceCountry() {
  for (final l in PlatformDispatcher.instance.locales) {
    final c = countryByCode(l.countryCode);
    if (c != null) return c;
  }
  return null;
}
