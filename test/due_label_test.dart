import 'package:flutter_test/flutter_test.dart';
import 'package:wince/data.dart';
import 'package:wince/item_tile.dart';
import 'package:wince/upcoming.dart';

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

  test('days count across a DST change and Upcoming groups by them', () {
    expect(daysUntil(DateTime(2026, 3, 30), DateTime(2026, 3, 29)), 1); // UK clocks go forward: a 23-hour day
    final now = DateTime(2026, 11, 4, 23, 45);
    expect(dueGroup(DateTime(2026, 11, 4, 23, 59), now), 'Next 24 hours');
    expect(dueGroup(DateTime(2026, 11, 5, 0, 10), now), 'This week'); // tomorrow, like its "Tomorrow" label
    expect(dueGroup(DateTime(2026, 11, 20), now), 'Later this month');
    expect(dueGroup(DateTime(2026, 12, 1), now), 'Later');
    expect(dueGroup(null, now), 'Later');
  });

  test('priceTag uses the symbol, drops .00 and adds the cycle', () {
    expect(priceTag(20, 'GBP', 'monthly'), '£20/mo');
    expect(priceTag(78, 'GHS', 'quarterly'), 'GH₵78/qtr');
    expect(priceTag(9.5, 'USD'), '\$9.50');
    expect(priceTag(1200, 'EUR', 'yearly'), '€1,200/yr');
  });
}
