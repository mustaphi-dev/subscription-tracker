import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'lock.dart';
import 'ui.dart';

/// Has this device seen onboarding? Loaded before runApp so the router can redirect synchronously.
final onboarded = ValueNotifier(false);
const _storage = FlutterSecureStorage();

Future<void> loadOnboarded() async => onboarded.value = await _storage.read(key: 'onboarded') == 'yes';

Future<void> finishOnboarding() async {
  await _storage.write(key: 'onboarded', value: 'yes');
  onboarded.value = true;
}

// ───────── Splash ─────────

/// Cold-start brand moment layered over the app; fades away on its own.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key});
  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _visible = true, _gone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        onEnd: () => setState(() => _gone = true),
        child: ColoredBox(
          color: kBg,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(alignment: Alignment.center, children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [kAccent.withValues(alpha: 0.35), kAccent.withValues(alpha: 0)]),
                  ),
                ).animate().scale(begin: const Offset(0.4, 0.4), duration: 900.ms, curve: Curves.easeOutCubic).fadeIn(),
                const AppLogo(size: 84)
                    .animate()
                    .scale(begin: const Offset(0.5, 0.5), duration: 700.ms, curve: springBounce)
                    .fadeIn(duration: 200.ms)
                    .then(delay: 120.ms)
                    .rotate(begin: 0, end: 0.5, duration: 600.ms, curve: Curves.easeInOutCubic),
              ]),
              const SizedBox(height: 8),
              Text('Subtracker', style: display(26))
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 400.ms)
                  .slideY(begin: 0.4, curve: springOut, duration: 500.ms),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────── Onboarding ─────────
// Each page is a full-colour card carrying a real piece of the product. Everything inside
// is driven by the page position, so dragging between pages scrubs the animation.

/// Eased 0→1 progress of [t] across the window [a, b].
double _span(double t, double a, double b) => Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Fade + rise driven by [r] (0 hidden, 1 in place).
Widget _rise(double r, Widget child, {double dy = 16}) =>
    Opacity(opacity: r, child: Transform.translate(offset: Offset(0, (1 - r) * dy), child: child));

/// Dark ink used for type drawn directly on the coloured cards.
const _ink = kBg;
Color _inkA(double a) => _ink.withValues(alpha: a);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _copy = [
    ('Every renewal,\nbefore it hits.', 'Subscriptions, Pay in 3 and income from all your accounts, in the order the money actually moves.'),
    ('Trials end on\nyour terms.', 'We remind you 7 days, 3 days and 24 hours before a free trial starts charging.'),
    ('See a shortfall\ncoming.', 'If this week\'s renewals would overdraw an account, you\'ll know how much to move and by when.'),
  ];
  static const _cards = [
    ('RENEWALS', Color(0xFFA99DFF)),
    ('FREE TRIALS', Color(0xFFFFC266)),
    ('SHORTFALLS', Color(0xFFFF8F80)),
  ];

  bool get _last => _page == _copy.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    HapticFeedback.mediumImpact();
    await finishOnboarding();
    if (mounted) context.go('/signin');
  }

  void _next() {
    if (_last) {
      _done();
      return;
    }
    HapticFeedback.selectionClick();
    _pages.nextPage(duration: const Duration(milliseconds: 560), curve: Curves.easeInOutCubic);
  }

  Widget _art(int i, double t) => switch (i) {
        0 => _RenewalsArt(t),
        1 => _TrialArt(t),
        _ => _ShortfallArt(t, _cards[2].$2),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          // One-off intro so the first card lands on open; afterwards the page position drives everything.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1300),
            builder: (_, intro, _) => AnimatedBuilder(
              animation: _pages,
              builder: (_, _) {
                final pos = _pages.hasClients && _pages.position.haveDimensions ? _pages.page ?? 0 : _page.toDouble();
                final land = _span(intro, 0, 0.5);
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                    child: Row(children: [
                      Expanded(child: _Progress(pos: pos, count: _copy.length)),
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        opacity: _last ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(onPressed: _last ? null : _done, child: const Text('Skip', style: TextStyle(color: kMuted))),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _copy.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) {
                        final d = pos - i;
                        final t = (1 - d.abs()).clamp(0.0, 1.0) * intro;
                        final (tag, color) = _cards[i];
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Opacity(
                                opacity: land,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - land) * 48),
                                  child: Transform.scale(
                                    scale: 1 - 0.07 * d.abs(),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(36),
                                      child: ColoredBox(
                                        color: color,
                                        child: Stack(children: [
                                          Positioned(
                                            left: 24,
                                            top: 22,
                                            child: Text(tag, style: TextStyle(color: _inkA(0.55), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                                          ),
                                          Positioned(
                                            right: 24,
                                            top: 22,
                                            child: Text('0${i + 1}', style: TextStyle(color: _inkA(0.55), fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                          ),
                                          // Art lags the card for depth, clipped to the card.
                                          Positioned.fill(
                                            child: Transform.translate(
                                              offset: Offset(d * 140, 0),
                                              child: Padding(
                                                padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
                                                child: LayoutBuilder(
                                                  builder: (_, c) => Center(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: SizedBox(width: c.maxWidth, child: _art(i, t)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _rise(_span(t, 0.2, 0.8), Text(_copy[i].$1, style: display(32)), dy: 10),
                              const SizedBox(height: 10),
                              _rise(
                                _span(t, 0.35, 0.95),
                                Text(_copy[i].$2, style: const TextStyle(color: kMuted, fontSize: 15, height: 1.45)),
                                dy: 10,
                              ),
                            ]),
                          ),
                        ]);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                    child: FilledButton(
                      onPressed: _next,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(_last ? 'Get started' : 'Continue', key: ValueKey(_last)),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
      );
}

/// Story-style segments that fill continuously with the page position.
class _Progress extends StatelessWidget {
  const _Progress({required this.pos, required this.count});
  final double pos;
  final int count;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var k = 0; k < count; k++) ...[
          if (k > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (pos - k + 1).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: kText, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ),
        ],
      ]);
}

/// Dark app surface sitting on a coloured card.
Widget _panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _inkA(0.25), blurRadius: 32, offset: const Offset(0, 16))],
      ),
      child: child,
    );

const _small = TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6);

/// Page 1: the week's ledger, rows landing one after another.
class _RenewalsArt extends StatelessWidget {
  const _RenewalsArt(this.t);
  final double t;

  static final _rows = [
    ('TUE', '12', 'Spotify', 'Revolut', '−£11.99', providerColors['revolut']!),
    ('FRI', '15', 'Klarna', 'Lloyds · 2 of 3', '−£35.00', providerColors['lloyds']!),
    ('MON', '18', 'Netflix', 'Trial ends', '−£10.99', kAmber),
    ('THU', '21', 'Salary', 'Lloyds', '+£2,140.00', kMint),
  ];

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _rise(
          _span(t, 0, 0.45),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Next 10 days', style: display(16, color: _inkA(0.65), weight: FontWeight.w600)),
            BigMoney(57.98, 'GBP', size: 44, color: _ink),
          ]),
        ),
        const SizedBox(height: 16),
        _rise(
          _span(t, 0.1, 0.55),
          _panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            Column(children: [
              for (var k = 0; k < _rows.length; k++) _rise(_span(t, 0.2 + 0.1 * k, 0.6 + 0.1 * k), _row(_rows[k], first: k == 0), dy: 10),
            ]),
          ),
          dy: 32,
        ),
      ]);

  Widget _row((String, String, String, String, String, Color) r, {required bool first}) {
    final (dow, day, name, sub, amount, color) = r;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: kLine))),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dow, style: _small.copyWith(fontSize: 10)),
            Text(day, style: display(18)),
          ]),
        ),
        Container(width: 3, height: 28, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(sub, style: caption),
          ]),
        ),
        Text(amount, style: TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular, color: amount.startsWith('+') ? kMint : kText)),
      ]),
    );
  }
}

/// Page 2: a 7-day trial ticking down, reminders marked, and the push you'd get at 3 days.
class _TrialArt extends StatelessWidget {
  const _TrialArt(this.t);
  final double t;

  static const _marks = {0: '7 days', 4: '3 days', 6: '1 day'};

  @override
  Widget build(BuildContext context) {
    final elapsed = 4 * _span(t, 0.1, 0.75);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _rise(
        _span(t, 0, 0.4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('${7 - elapsed.round()}', style: display(96, color: _ink)),
          const SizedBox(width: 10),
          Text('days left on\nyour Netflix trial', style: display(17, color: _inkA(0.7), weight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        for (var k = 0; k < 7; k++) ...[
          if (k > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 8,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: _inkA(0.15), borderRadius: BorderRadius.circular(4)),
              child: FractionallySizedBox(
                widthFactor: (elapsed - k).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4))),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (var k = 0; k < 7; k++) ...[
          if (k > 0) const SizedBox(width: 4),
          Expanded(
            child: _marks[k] == null
                ? const SizedBox()
                : Builder(builder: (_) {
                    final hit = k == 0 || elapsed >= k;
                    return Row(children: [
                      Icon(Icons.notifications_rounded, size: 13, color: hit ? _ink : _inkA(0.35)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(_marks[k]!,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: hit ? _ink : _inkA(0.45))),
                      ),
                    ]);
                  }),
          ),
        ],
      ]),
      const SizedBox(height: 24),
      // The actual reminder, arriving as the bar reaches 3 days.
      _rise(
        _span(t, 0.7, 1),
        _panel(
          padding: const EdgeInsets.all(14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppLogo(size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Text('Subtracker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Spacer(),
                  Text('now', style: caption),
                ]),
                const SizedBox(height: 2),
                const Text('Netflix trial ends in 3 days', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Then £10.99 a month from 14 Dec. Cancel now if you won\'t use it.', style: caption.copyWith(height: 1.35)),
              ]),
            ),
          ]),
        ),
        dy: -24,
      ),
    ]);
  }
}

/// Page 3: this week's charges fill a bar past the account balance, then the alert lands.
class _ShortfallArt extends StatelessWidget {
  const _ShortfallArt(this.t, this.card);
  final double t;
  final Color card;

  static const _balance = 42.67;
  static const _charges = [35.00, 11.99, 10.99, 8.99]; // sums to 66.97 → £24.30 short

  @override
  Widget build(BuildContext context) {
    final fill = _span(t, 0.15, 0.8);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _rise(
        _span(t, 0, 0.4),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Revolut balance', style: display(16, color: _inkA(0.65), weight: FontWeight.w600)),
          BigMoney(_balance, 'GBP', size: 44, color: _ink),
        ]),
      ),
      const SizedBox(height: 20),
      SizedBox(height: 28, width: double.infinity, child: CustomPaint(painter: _BarPainter(fill, card))),
      const SizedBox(height: 8),
      Row(children: [
        Text('Due by Thursday', style: TextStyle(color: _inkA(0.65), fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('£66.97', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontFeatures: tabular)),
      ]),
      const SizedBox(height: 24),
      _rise(
        _span(t, 0.7, 1),
        _panel(
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: kCrimson.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.south_east_rounded, color: kCrimson, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('£24.30 short', style: display(18, color: kCrimson)),
                const Text('Top up Revolut before Thursday', style: caption),
              ]),
            ),
          ]),
        ),
        dy: 24,
      ),
    ]);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.fill, this.card);
  final double fill;
  final Color card;

  @override
  void paint(Canvas canvas, Size size) {
    final total = _ShortfallArt._charges.fold(0.0, (s, c) => s + c);
    final mark = size.width * _ShortfallArt._balance / total;
    final bar = Rect.fromLTWH(0, (size.height - 14) / 2, size.width, 14);
    final r = RRect.fromRectAndRadius(bar, const Radius.circular(7));
    canvas.drawRRect(r, Paint()..color = _inkA(0.15));

    canvas.save();
    canvas.clipRRect(r);
    final end = size.width * fill;
    canvas.drawRect(Rect.fromLTRB(0, bar.top, end.clamp(0, mark), bar.bottom), Paint()..color = _ink);
    // Deeper red than kCrimson: kCrimson disappears against the coral card.
    if (end > mark) canvas.drawRect(Rect.fromLTRB(mark, bar.top, end, bar.bottom), Paint()..color = const Color(0xFFC0182B));
    // Gaps between individual charges, cut in the card colour.
    var x = 0.0;
    for (final c in _ShortfallArt._charges.take(_ShortfallArt._charges.length - 1)) {
      x += size.width * c / total;
      if (x < end) canvas.drawRect(Rect.fromLTWH(x - 1.5, bar.top, 3, bar.height), Paint()..color = card);
    }
    canvas.restore();

    // Balance marker.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(mark - 1.5, 0, 3, size.height), const Radius.circular(2)), Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.fill != fill || o.card != card;
}
