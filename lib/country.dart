import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'countries.dart';
import 'data.dart';
import 'ui.dart';

/// Country picker. Shown once after sign-up (sets the display currency too), and from
/// Profile to change it later (country only).
class CountryScreen extends StatefulWidget {
  const CountryScreen({super.key, this.current});

  /// Set when editing from Profile; null during first-run setup.
  final String? current;

  @override
  State<CountryScreen> createState() => _CountryScreenState();
}

class _CountryScreenState extends State<CountryScreen> {
  final _search = TextEditingController();
  late final Country? _guess = countryByCode(widget.current) ?? deviceCountry();
  late Country? _picked = _guess;
  bool _busy = false;

  bool get _editing => widget.current != null;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _picked;
    if (c == null) return;
    setState(() => _busy = true);
    try {
      await setCountry(c.code, currency: _editing ? null : c.currency);
      if (mounted && _editing) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, 'Couldn\'t save your country: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = [
      // The phone's own region first, so most people just tap Continue.
      if (q.isEmpty && _guess != null) _guess,
      for (final c in countries)
        if (c != _guess || q.isNotEmpty)
          if (q.isEmpty || c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q) c,
    ];

    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(icon: const Icon(CupertinoIcons.chevron_back), onPressed: () => Navigator.of(context).pop()),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, _editing ? 4 : 40, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where do you bank?', style: display(32)),
                    const SizedBox(height: 10),
                    Text(
                      _editing
                          ? 'This decides which banks you can connect automatically.'
                          : 'We\'ll set your currency and show the banks you can connect. You can change it later in Profile.',
                      style: const TextStyle(color: kMuted, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(hintText: 'Search countries', prefixIcon: Icon(CupertinoIcons.search, size: 18)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final selected = c == _picked;
                    return Pressable(
                      scale: 0.99,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _picked = c);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: selected ? kSurfaceHi : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Text(c.flag, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    c.bankLinking ? '${c.currency} · Bank sync available' : c.currency,
                                    style: caption.copyWith(color: c.bankLinking ? kMint : kMuted),
                                  ),
                                ],
                              ),
                            ),
                            if (selected) const Icon(CupertinoIcons.checkmark, color: kMint, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: FilledButton(
                  onPressed: _picked == null || _busy ? null : _save,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kBg))
                      : Text(_picked == null ? 'Pick your country' : 'Continue with ${_picked!.name}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
