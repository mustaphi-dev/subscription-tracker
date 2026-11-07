import 'package:flutter_test/flutter_test.dart';
import 'package:wince/data.dart';
import 'package:wince/item_tile.dart';

PaymentSource src(String provider, [String? institution]) =>
    PaymentSource({'id': '1', 'provider': provider, 'account_name': 'Main', 'currency': 'GBP', 'institution': institution});

void main() {
  test('bankAppUrl matches provider or institution name', () {
    expect(bankAppUrl(src('revolut')), 'https://revolut.com/app');
    expect(bankAppUrl(src('ob-monzo', 'Monzo')), 'https://www.monzo.com');
    expect(bankAppUrl(src('other', 'Unknown Credit Union')), isNull);
    expect(bankAppUrl(null), isNull);
  });
}
