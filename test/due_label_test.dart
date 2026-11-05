import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/item_tile.dart';
import 'package:subtracker/ui.dart';

void main() {
  test('dueLabel rounds to calendar days, weeks and months', () {
    final now = DateTime(2026, 11, 4, 23, 45);
    expect(dueLabel(DateTime(2026, 11, 4, 23, 59), now), 'Today');
    expect(dueLabel(DateTime(2026, 11, 5, 0, 10), now), 'Tomorrow'); // 25 minutes away is still tomorrow
    expect(dueLabel(DateTime(2026, 11, 11), now), 'In 7 days');
    expect(dueLabel(DateTime(2026, 11, 25), now), 'In 3 weeks');
    expect(dueLabel(DateTime(2027, 2, 4), now), 'In 3 months');
    expect(dueLabel(DateTime(2026, 11, 3), now), 'Ended');
  });

  test('priceTag uses the symbol, drops .00 and adds the cycle', () {
    expect(priceTag(20, 'GBP', 'monthly'), '£20/mo');
    expect(priceTag(78, 'GHS', 'quarterly'), 'GH₵78/qtr');
    expect(priceTag(9.5, 'USD'), '\$9.50');
    expect(priceTag(1200, 'EUR', 'yearly'), '€1,200/yr');
  });
}
