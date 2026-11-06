import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/data.dart';

void main() {
  test('base currency is cleaned to an ISO code or falls back to GBP', () {
    expect(isoCurrency('GHS'), 'GHS');
    expect(isoCurrency('ghs '), 'GHS');
    expect(isoCurrency('G  '), 'GBP');
    expect(isoCurrency(null), 'GBP');
  });
}
