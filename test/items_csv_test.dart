import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wince/data.dart';
import 'package:wince/export.dart';

void main() {
  test('itemsCsv quotes awkward fields and formats dates', () {
    final i = FinancialItem({
      'id': '1', 'item_type': 'subscription', 'merchant_name': 'Acme, "Pro"', 'original_amount': 9.99,
      'original_currency': 'GBP', 'billing_cycle': 'monthly', 'status': 'active', 'auto_detected_via': 'manual',
      'next_renewal_date': '2026-12-01',
    });
    final lines = itemsCsv([i]).split('\n');
    expect(lines, hasLength(2));
    expect(lines[1], '"Acme, ""Pro""",subscription,active,9.99,GBP,monthly,2026-12-01,,,0.0,');
  });

  test('itemsXlsx builds a readable workbook', () {
    final i = FinancialItem({
      'id': '1', 'item_type': 'subscription', 'merchant_name': 'Netflix', 'original_amount': 9.99,
      'original_currency': 'GBP', 'billing_cycle': 'monthly', 'status': 'active', 'auto_detected_via': 'manual',
    });
    final book = Excel.decodeBytes(itemsXlsx([i]));
    final rows = book.tables.values.first.rows;
    expect(rows, hasLength(2));
    expect(rows[1][0]?.value.toString(), 'Netflix');
  });
}
