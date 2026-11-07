import 'package:flutter_test/flutter_test.dart';
import 'package:wince/data.dart';

FinancialItem item(Map<String, dynamic> m) => FinancialItem({
      'id': m['merchant_name'],
      'original_currency': 'GBP',
      'billing_cycle': 'monthly',
      'status': 'active',
      'auto_detected_via': 'manual',
      ...m,
    });

void main() {
  final from = DateTime(2026, 1, 1), to = DateTime(2026, 7, 1);

  test('monthly sub clamps 31st to month end', () {
    final c = chargesBetween([
      item({'merchant_name': 'Sub', 'item_type': 'subscription', 'original_amount': 10, 'gbp_equivalent_amount': 10, 'next_renewal_date': '2026-01-31'}),
    ], from, to);
    expect(c.map((e) => '${e.date.month}/${e.date.day}'), ['1/31', '2/28', '3/31', '4/30', '5/31', '6/30']);
    expect(c.first.amount, -10);
  });

  test('installment stops after remaining payments', () {
    final c = chargesBetween([
      item({'merchant_name': 'Pay in 3', 'item_type': 'installment', 'original_amount': 35, 'gbp_equivalent_amount': 35,
        'next_renewal_date': '2026-02-14', 'installment_total_count': 3, 'installment_paid_count': 1}),
    ], from, to);
    expect(c.length, 2);
  });

  test('trial charges post-trial amount from end date; income is positive; yearly once', () {
    final c = chargesBetween([
      item({'merchant_name': 'Trial', 'item_type': 'free_trial', 'original_amount': 0, 'post_trial_amount': 8,
        'gbp_equivalent_amount': 8, 'trial_end_date': '2026-05-10T09:00:00Z'}),
      item({'merchant_name': 'Pay', 'item_type': 'income', 'original_amount': 2000, 'gbp_equivalent_amount': 2000, 'next_renewal_date': '2026-06-25'}),
      item({'merchant_name': 'Yearly', 'item_type': 'subscription', 'original_amount': 60, 'gbp_equivalent_amount': 60,
        'billing_cycle': 'yearly', 'next_renewal_date': '2026-03-01'}),
    ], from, to);
    expect(c.where((e) => e.item.merchant == 'Trial').map((e) => e.amount), [-8, -8]);
    expect(c.singleWhere((e) => e.item.merchant == 'Pay').amount, 2000);
    expect(c.where((e) => e.item.merchant == 'Yearly').length, 1);
  });
}
