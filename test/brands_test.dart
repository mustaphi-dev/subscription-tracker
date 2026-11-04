import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/brands.dart';

void main() {
  String? domain(String n) => logoQuery(n)?.domain;
  String? name(String n) => logoQuery(n)?.name;

  test('messy bank-feed names map to the right domain', () {
    expect(domain('NETFLIX.COM'), 'netflix.com');
    expect(domain('YouTube Music'), 'youtube.com');
    expect(domain('UBER *EATS'), 'ubereats.com');
    expect(domain('Uber *Trip'), 'uber.com');
    expect(domain('AMZN Mktp UK'), 'amazon.co.uk');
    expect(domain('Apple.com/bill'), 'apple.com');
    expect(domain('PAYPAL *NETFLIX'), 'netflix.com'); // processor prefix doesn't win
    expect(domain('TransferWise'), 'wise.com');
    expect(domain('Lloyds'), 'lloydsbank.com');
  });

  test('short aliases only match whole words', () {
    expect(domain('Amazon purchase'), 'amazon.co.uk'); // not Chase
    expect(domain('Skyscanner'), isNull); // not Sky
    expect(domain('Otherwise Gym'), isNull); // not Wise
  });

  test('unknown merchants become a cleaned name lookup', () {
    expect(name('Skyscanner Ltd'), 'skyscanner');
    expect(name('Acme Fitness 0042 Subscription'), 'acme fitness');
    expect(logoQuery('***'), isNull);
  });
}
