import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'ui.dart';

/// Every tracked item (cancelled ones too) as export rows, header first.
List<List<Object?>> itemsTable(List<FinancialItem> items) => [
      ['merchant', 'type', 'status', 'amount', 'currency', 'cycle', 'next_renewal', 'trial_end', 'post_trial_amount', 'total_spent', 'added'],
      for (final i in items)
        [i.merchant, i.type, i.status, i.amount, i.currency, i.cycle, i.nextRenewal, i.trialEnd, i.postTrialAmount, i.totalSpent, i.createdAt]
            .map((v) => v is DateTime ? v.toIso8601String().substring(0, 10) : v)
            .toList(),
    ];

String itemsCsv(List<FinancialItem> items) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return itemsTable(items).map((r) => r.map(cell).join(',')).join('\n');
}

List<int> itemsXlsx(List<FinancialItem> items) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  for (final r in itemsTable(items)) {
    sheet.appendRow([for (final v in r) v is num ? DoubleCellValue(v.toDouble()) : TextCellValue('${v ?? ''}')]);
  }
  return book.encode()!;
}

enum ExportFormat {
  csv('csv', 'text/csv'),
  xlsx('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  const ExportFormat(this.ext, this.mime);
  final String ext, mime;

  List<int> encode(List<FinancialItem> items) => this == csv ? utf8.encode(itemsCsv(items)) : itemsXlsx(items);
}

/// Everything tracked, as a CSV or Excel file through the share sheet (Files, Mail, Numbers…).
Future<void> exportItems(BuildContext context, ExportFormat format) async {
  try {
    final rows = await db.from('financial_items').select().order('created_at');
    final items = rows.map(FinancialItem.new).toList();
    final name = 'wince-${DateFormat('y-MM-dd').format(DateTime.now())}.${format.ext}';
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(format.encode(items)), mimeType: format.mime)],
      fileNameOverrides: [name],
    ));
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t export your data. Try again in a moment.', e);
  }
}

class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget option(FaIconData icon, String title, String sub, ExportFormat format) => Pressable(
          scale: 0.99,
          onTap: () => exportItems(closeSheet(context), format),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              FaIcon(icon, size: 24, color: kText),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  Text(sub, style: caption),
                ]),
              ),
              const Icon(CupertinoIcons.chevron_right, size: 16, color: kFaint),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Export data', style: display(22)),
        const SizedBox(height: 4),
        const Text('Everything you track, including cancelled items.', style: TextStyle(color: kMuted)),
        const SizedBox(height: 8),
        option(FontAwesomeIcons.fileLines, 'CSV', 'Open with Numbers and Google Sheets', ExportFormat.csv),
        const Divider(height: 1, color: kLine),
        option(FontAwesomeIcons.fileExcel, 'Excel', 'An .xlsx workbook for Microsoft Excel', ExportFormat.xlsx),
      ]),
    );
  }
}
