import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'brands.dart';
import 'currency.dart';
import 'data.dart';
import 'ui.dart';

Future<void> scanReceipt(BuildContext context) async {
  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
  if (img == null || !context.mounted) return;
  showToast(context, 'Reading receipt…', icon: CupertinoIcons.sparkles, tone: kAccent, duration: const Duration(seconds: 20));
  try {
    final res = await parseReceipt({'image_base64': base64Encode(await img.readAsBytes()), 'media_type': img.mimeType ?? 'image/jpeg'});
    if (!context.mounted) return;
    final item = res['item'], dup = res['duplicate'];
    if (item != null) {
      showToast(context, 'Added ${item['merchant_name']}');
    } else if (dup != null) {
      showToast(context, 'You\'re already tracking ${dup['merchant_name']}', icon: CupertinoIcons.info_circle, tone: kAmber);
    } else {
      showToast(context, 'No trial or subscription found in that image', icon: CupertinoIcons.info_circle, tone: kAmber);
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Couldn\'t read that receipt. Try a clearer photo.', e);
  }
}

/// What the nav's plus offers: scan, type it in, or forward emails.
class AddSheet extends StatelessWidget {
  const AddSheet({super.key});
  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String title, String sub, VoidCallback onTap) => Surface(
          color: kSurfaceHi,
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: kText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(sub, style: caption),
              ]),
            ),
            const Icon(CupertinoIcons.chevron_right, color: kFaint),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 16), child: Text('Add', style: display(24))),
        option(CupertinoIcons.doc_text_viewfinder, 'Scan a receipt', 'Picks up the trial end date and price',
            () => scanReceipt(closeSheet(context))),
        const SizedBox(height: 10),
        option(CupertinoIcons.pencil, 'Add manually', 'Subscription, trial, pay later or income',
            () => showSheet(closeSheet(context), const ManualItemForm())),
        const SizedBox(height: 10),
        option(FontAwesomeIcons.envelope.data, 'Forward emails', 'Trials, subscriptions and pay later',
            () => closeSheet(context).push('/forwarding')),
      ]),
    );
  }
}

class ManualItemForm extends ConsumerStatefulWidget {
  const ManualItemForm({super.key});
  @override
  ConsumerState<ManualItemForm> createState() => _ManualItemFormState();
}

class _ManualItemFormState extends ConsumerState<ManualItemForm> {
  final _merchant = TextEditingController();
  final _amount = TextEditingController();
  final _installTotal = TextEditingController(text: '3');
  String _type = 'subscription', _cycle = 'monthly';
  late String _currency = ref.read(baseProvider);
  String? _sourceId;
  DateTime _date = DateTime.now().add(const Duration(days: 7));

  static final _types = itemTypes.keys.toList();

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text);
    if (_merchant.text.trim().isEmpty || amount == null) {
      showError(context, 'Add a name and an amount');
      return;
    }
    final trial = _type == 'free_trial';
    final installments = int.tryParse(_installTotal.text);
    try {
      await addItem({
        'item_type': _type,
        'merchant_name': _merchant.text.trim(),
        'original_amount': trial ? 0 : amount,
        'original_currency': _currency,
        'post_trial_amount': trial ? amount : null,
        'billing_cycle': _cycle,
        'payment_source_id': _sourceId,
        'next_renewal_date': DateFormat('yyyy-MM-dd').format(_date),
        if (trial) 'trial_end_date': _date.toUtc().toIso8601String(),
        if (_type == 'installment') ...{'installment_total_count': installments, 'installment_remaining_balance': amount * (installments ?? 0)},
      });
    } catch (e) {
      if (mounted) showError(context, 'Couldn\'t save that. Try again.', e);
      return;
    }
    if (!mounted) return;
    showToast(context, 'Added ${_merchant.text.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider).value ?? [];
    final base = ref.watch(baseProvider);
    Widget field(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: caption),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
    Widget box(Widget child) => Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(14)),
      child: child,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text('New item', style: display(24)),
          ),
          Segmented(
            labels: [for (final t in itemTypes.values) t.form],
            selected: _types.indexOf(_type),
            onSelect: (i) => setState(() => _type = _types[i]),
          ),
          const SizedBox(height: 16),
          field(
            'Name',
            TextField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Netflix'),
            ),
          ),
          field(
            switch (_type) {
              'free_trial' => 'Charge after the trial',
              'installment' => 'Each payment',
              'income' => 'Amount received',
              _ => 'Amount',
            },
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFeatures: tabular),
                    decoration: const InputDecoration(hintText: '0.00'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: SelectField<String>(
                    title: 'Currency',
                    options: [for (final (code, _, name) in currencyChoices(base)) (code, code, name)],
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v),
                  ),
                ),
              ],
            ),
          ),
          if (_type == 'installment') field('Number of payments', TextField(controller: _installTotal, keyboardType: TextInputType.number)),
          Row(
            children: [
              Expanded(
                child: field(
                  'Repeats',
                  SelectField<String>(
                    title: 'Repeats',
                    options: [for (final MapEntry(key: k, value: c) in cycles.entries) (k, c.label, c.hint)],
                    value: _cycle,
                    onChanged: (v) => setState(() => _cycle = v),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: field(
                  _type == 'free_trial' ? 'Trial ends' : 'Next date',
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime(2100));
                      if (d != null) setState(() => _date = d);
                    },
                    child: box(Text(DateFormat('d MMM y').format(_date))),
                  ),
                ),
              ),
            ],
          ),
          field(
            _type == 'income' ? 'Paid into' : 'Paid from',
            SelectField<String>(
              title: _type == 'income' ? 'Paid into' : 'Paid from',
              hint: sources.isEmpty ? 'No accounts yet' : 'Choose an account',
              options: [for (final s in sources) (s.id, s.bank, '${s.name} · ${money(s.balance, s.currency)}')],
              value: _sourceId,
              onChanged: (v) => setState(() => _sourceId = v),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
