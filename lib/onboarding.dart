import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'lock.dart';
import 'scene3d.dart';
import 'ui.dart';

/// Has this device seen onboarding? Loaded before runApp so the router can redirect synchronously.
final onboarded = ValueNotifier(false);
const _storage = FlutterSecureStorage();

Future<void> loadOnboarded() async => onboarded.value = await _storage.read(key: 'onboarded') == 'yes';

Future<void> finishOnboarding() async {
  await _storage.write(key: 'onboarded', value: 'yes');
  onboarded.value = true;
}

/// Eased 0→1 progress of [t] across the window [a, b].
double _span(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Fade + rise driven by [r] (0 hidden, 1 in place).
Widget _rise(double r, Widget child, {double dy = 16}) =>
    Opacity(opacity: r.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - r) * dy), child: child));

const _brandLight = [Color(0xFF6C4BFF), Color(0xFF2F6BFF), Color(0xFF8B7CFF)];

// ───────── Splash ─────────

/// Cold-start brand moment layered over the app: the mark spins in as a 3D token, an
/// orbit of renewals draws around it, then the whole thing dissolves into the app.
/// Tap to skip. Collapses to a short fade when the OS asks for reduced motion.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key});
  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  late final _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final _clock = SceneClock(this);
  bool _started = false, _leaving = false, _gone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.freeze();
      _intro.value = 1;
      Future.delayed(const Duration(milliseconds: 600), _leave);
      return;
    }
    _intro.forward().then((_) => _leave());
    Future.delayed(const Duration(milliseconds: 620), () {
      if (mounted && !_leaving) HapticFeedback.lightImpact();
    });
  }

  void _leave() {
    if (!mounted || _leaving) return;
    _leaving = true;
    _intro.stop();
    _exit.forward().then((_) {
      if (!mounted) return;
      _clock.freeze();
      setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _exit, _clock]),
      builder: (context, _) {
        final t = _intro.value, e = Curves.easeInCubic.transform(_exit.value), now = _clock.value;
        final glow = _span(t, 0, 0.4);
        final spin = _span(t, 0.04, 0.55, Curves.easeOutBack);
        final settled = _span(t, 0.4, 0.9);
        final ry = -1.3 * (1 - spin) + 0.22 * math.sin(now * 0.9) * settled;
        final rx = 0.55 * (1 - spin) + 0.14 + 0.06 * math.cos(now * 0.7) * settled;
        final ring = _span(t, 0.25, 0.8, Curves.easeInOutCubic);
        final spinRing = now * 0.55 - 1.2;
        const word = 'Subtracker';

        OrbitRing orbit(bool front) => OrbitRing(
              radius: 118,
              tilt: 1.15,
              spin: spinRing,
              progress: ring,
              front: front,
              satellites: const [Color(0xFF34D399), Color(0xFFFFB547), Color(0xFFFF8F80)],
            );

        return IgnorePointer(
          ignoring: _leaving,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _leave,
            child: Opacity(
              opacity: 1 - e,
              child: Stack(fit: StackFit.expand, children: [
                Aurora(clock: _clock, colors: _brandLight, intensity: glow, focus: const Alignment(0, -0.2)),
                Center(
                  child: Transform.scale(
                    scale: 1 + 0.12 * e,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox.square(
                        dimension: 280,
                        child: Stack(alignment: Alignment.center, children: [
                          Positioned.fill(child: CustomPaint(painter: orbit(false))),
                          IconToken(
                            size: 96,
                            rx: rx,
                            ry: ry,
                            opacity: _span(t, 0.02, 0.2),
                            transform: place(Offset(0, -5 * math.sin(now * 1.3) * settled), rx: rx, ry: ry, scale: 0.55 + 0.45 * spin),
                          ),
                          Positioned.fill(child: CustomPaint(painter: orbit(true))),
                        ]),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        for (var k = 0; k < word.length; k++)
                          _rise(_span(t, 0.38 + 0.025 * k, 0.68 + 0.025 * k), Text(word[k], style: display(34)), dy: 18),
                      ]),
                      const SizedBox(height: 8),
                      _rise(
                        _span(t, 0.66, 0.96),
                        const Text('Every renewal, before it hits.', style: TextStyle(color: kMuted, fontSize: 15)),
                        dy: 8,
                      ),
                      const SizedBox(height: 60),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ───────── Onboarding ─────────
// A full-bleed 3D scene per page over a light field that changes colour with the page.
// Scenes are driven by the page position, so dragging between pages scrubs both the
// motion and the lighting; a scene clock adds a slow idle float on top.

class _Page {
  const _Page(this.tag, this.title, this.body, this.accent, this.light);
  final String tag, title, body;
  final Color accent;
  final List<Color> light;
}

const _pagesData = [
  _Page(
    'RENEWALS',
    'Every renewal,\nbefore it hits.',
    'Subscriptions, Pay in 3 and income from all your accounts, in the order the money actually moves.',
    Color(0xFFA99DFF),
    _brandLight,
  ),
  _Page(
    'FREE TRIALS',
    'Trials end on\nyour terms.',
    'We remind you 7 days, 3 days and 24 hours before a free trial starts charging.',
    Color(0xFFFFC266),
    [Color(0xFFFFB547), Color(0xFFFF7A45), Color(0xFF8B5CFF)],
  ),
  _Page(
    'SHORTFALLS',
    'See a shortfall\ncoming.',
    'If this week\'s renewals would overdraw an account, you\'ll know how much to move and by when.',
    Color(0xFFFF8F80),
    [Color(0xFFFF5C6C), Color(0xFFFF8F80), Color(0xFF6C4BFF)],
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final _clock = SceneClock(this);
  int _page = 0;
  bool _checkedMotion = false;

  bool get _last => _page == _pagesData.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedMotion) {
      _checkedMotion = true;
      if (MediaQuery.disableAnimationsOf(context)) _clock.freeze();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _clock.dispose();
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
    _pages.nextPage(duration: const Duration(milliseconds: 620), curve: Curves.easeInOutCubic);
  }

  List<Color> _lightAt(double pos) {
    final i = pos.floor().clamp(0, _pagesData.length - 1), j = pos.ceil().clamp(0, _pagesData.length - 1);
    final f = pos - pos.floor();
    return [for (var k = 0; k < 3; k++) Color.lerp(_pagesData[i].light[k], _pagesData[j].light[k], f)!];
  }

  Widget _scene(int i, double t, double d, double now) => switch (i) {
        0 => _OrbitScene(t: t, d: d, now: now),
        1 => _TrialScene(t: t, d: d, now: now),
        _ => _ShortfallScene(t: t, d: d, now: now),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: TweenAnimationBuilder<double>(
          // One-off entrance; afterwards the page position drives everything.
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1400),
          builder: (_, intro, _) => AnimatedBuilder(
            animation: Listenable.merge([_pages, _clock]),
            builder: (_, _) {
              final pos = _pages.hasClients && _pages.position.haveDimensions ? _pages.page ?? 0 : _page.toDouble();
              final now = _clock.value;
              return Stack(fit: StackFit.expand, children: [
                Aurora(clock: _clock, colors: _lightAt(pos), intensity: _span(intro, 0, 0.6), focus: const Alignment(0, -0.45)),
                SafeArea(
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: _Progress(pos: pos, count: _pagesData.length),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (_, c) {
                        final heroH = c.maxHeight * 0.62;
                        return Stack(children: [
                          // Shared 3D stage behind the swipeable copy.
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: heroH,
                            child: ExcludeSemantics(
                              child: Stack(children: [
                                for (var i = 0; i < _pagesData.length; i++)
                                  if ((pos - i).abs() < 1)
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity: (1 - (pos - i).abs()).clamp(0.0, 1.0),
                                        child: Transform.translate(
                                          offset: Offset(-(pos - i) * 90, (1 - _span(intro, 0, 0.7)) * 40),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: SizedBox(
                                              width: 360,
                                              height: 400,
                                              child: _scene(i, (1 - (pos - i).abs()).clamp(0.0, 1.0) * intro, pos - i, now),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                              ]),
                            ),
                          ),
                          PageView.builder(
                            controller: _pages,
                            itemCount: _pagesData.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) {
                              final t = (1 - (pos - i).abs()).clamp(0.0, 1.0) * intro;
                              final p = _pagesData[i];
                              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                SizedBox(height: heroH),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      _rise(
                                        _span(t, 0.1, 0.6),
                                        Row(children: [
                                          Container(width: 6, height: 6, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                                          const SizedBox(width: 8),
                                          Text('0${i + 1}  ·  ${p.tag}',
                                              style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                                        ]),
                                        dy: 8,
                                      ),
                                      const SizedBox(height: 12),
                                      _rise(_span(t, 0.2, 0.8), Text(p.title, style: display(34)), dy: 12),
                                      const SizedBox(height: 10),
                                      _rise(
                                        _span(t, 0.35, 0.95),
                                        Text(p.body, style: const TextStyle(color: kMuted, fontSize: 15, height: 1.45)),
                                        dy: 12,
                                      ),
                                    ]),
                                  ),
                                ),
                              ]);
                            },
                          ),
                        ]);
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                      child: _rise(
                        _span(intro, 0.4, 1),
                        FilledButton(
                          onPressed: _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(_last ? 'Get started' : 'Continue', key: ValueKey(_last)),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Opacity(
                        opacity: _span(intro, 0.5, 1),
                        child: TextButton(
                          onPressed: _done,
                          child: const Text('I already have an account', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]);
            },
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
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(2)),
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

// ───────── Scenes ─────────
// Each scene is laid out on a 360×400 stage around its centre. [t] is how "on" the page is
// (0→1), [d] the signed distance from the current page (drives turn-away while swiping),
// [now] the idle clock in seconds.

/// Glassy dark face used by tiles and notifications.
const _glass = BoxDecoration(
  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E2129), Color(0xFF101217)]),
);

/// A brand mark from assets/brands, as a full-bleed app icon.
Widget _logo(String slug, {double? size}) => Image.asset('assets/brands/$slug.png',
    width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium);

/// Small rounded logo for inline use.
Widget _logoChip(String slug, double size) =>
    ClipRRect(borderRadius: BorderRadius.circular(size * 0.26), child: _logo(slug, size: size));

/// Dark price pill that hangs under a floating app icon.
Widget _pricePill(String price, Matrix4 m, double opacity) => Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform(
        transform: m,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xE6101217),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Text(price, style: const TextStyle(color: kText, fontSize: 11.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ),
      ),
    );

/// A brand app icon as a thick glossy slab.
Widget _iconSlab(String slug, {required Matrix4 m, required double rx, required double ry, double size = 68, double opacity = 1}) => Slab(
      size: Size.square(size),
      radius: size * 0.26,
      depth: size * 0.14,
      rx: rx,
      ry: ry,
      gloss: 0.3,
      edge: const Color(0xFF2A2D35),
      opacity: opacity,
      transform: m,
      face: _logo(slug),
    );

/// A node in a scene, sorted back-to-front before painting.
typedef _Node = (double z, Widget w);

Widget _stage(List<_Node> nodes, {List<Widget> under = const [], List<Widget> over = const []}) {
  nodes.sort((a, b) => b.$1.compareTo(a.$1));
  return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
    ...under,
    for (final n in nodes) n.$2,
    ...over,
  ]);
}

/// Page 1: the app token with this month's renewals orbiting it.
class _OrbitScene extends StatelessWidget {
  const _OrbitScene({required this.t, required this.d, required this.now});
  final double t, d, now;

  static const _tiles = [
    ('spotify', '£11.99'),
    ('netflix', '£10.99'),
    ('icloud', '£2.99'),
    ('klarna', '£35.00'),
    ('openai', '£20.00'),
    ('youtube', '£12.99'),
  ];
  static const _r = 150.0, _tilt = 0.5, _xs = 0.86;

  @override
  Widget build(BuildContext context) {
    final spin = now * 0.22 + d * 1.4 + (1 - t) * 1.6;
    final nodes = <_Node>[];
    for (var i = 0; i < _tiles.length; i++) {
      final a = spin + i * math.pi * 2 / _tiles.length;
      final x = _r * _xs * math.cos(a), z0 = _r * math.sin(a);
      final y = -z0 * math.sin(_tilt), z = z0 * math.cos(_tilt);
      final ti = _span(t, 0.05 + 0.07 * i, 0.55 + 0.07 * i, Curves.easeOutBack);
      final near = (1 - z / _r) / 2; // 1 nearest, 0 farthest
      final ry = -math.cos(a) * 0.5 + 0.15 * math.sin(now * 0.9 + i), rx = 0.18;
      final (slug, price) = _tiles[i];
      final fade = _span(t, 0.05 + 0.07 * i, 0.4 + 0.07 * i) * (0.5 + 0.5 * near);
      final scale = 0.6 + 0.4 * ti;
      nodes.add((z, _iconSlab(slug, m: place(Offset(x, y - 22), z: z, rx: rx, ry: ry, scale: scale), rx: rx, ry: ry, size: 64, opacity: fade)));
      nodes.add((z - 0.1, _pricePill(price, place(Offset(x, y + 22), z: z, scale: scale), fade * near)));
    }
    final tokRx = 0.2 + 0.05 * math.sin(now * 0.8), tokRy = 0.3 * math.sin(now * 0.5) - d * 0.9;
    nodes.add((
      0,
      IconToken(
        size: 92,
        rx: tokRx,
        ry: tokRy,
        opacity: _span(t, 0, 0.3),
        transform: place(Offset(0, -24 - 6 * math.sin(now * 1.2)), rx: tokRx, ry: tokRy, scale: 0.6 + 0.4 * _span(t, 0, 0.5, Curves.easeOutBack)),
      ),
    ));

    final ring = _span(t, 0.1, 0.8);
    OrbitRing orbit(bool front) => OrbitRing(radius: _r, tilt: _tilt, spin: spin, progress: ring, front: front, xScale: _xs);
    final chip = _span(t, 0.5, 1);

    return _stage(
      nodes,
      under: [Positioned.fill(top: -20, child: CustomPaint(painter: orbit(false)))],
      over: [
        Positioned.fill(top: -20, child: CustomPaint(painter: orbit(true))),
        Slab(
          size: const Size(220, 60),
          radius: 30,
          depth: 5,
          rx: 0.3,
          opacity: chip,
          transform: place(Offset(0, 158 + (1 - chip) * 30), rx: 0.3),
          face: DecoratedBox(
            decoration: _glass,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(children: [
                const Text('Next 10 days', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('£57.98', style: display(20)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Page 2: a trial card counting down, a bell token, and the reminder arriving in front.
class _TrialScene extends StatelessWidget {
  const _TrialScene({required this.t, required this.d, required this.now});
  final double t, d, now;

  static const _marks = {0: '7d', 4: '3d', 6: '1d'};

  @override
  Widget build(BuildContext context) {
    final elapsed = 4 * _span(t, 0.15, 0.75);
    final cardRx = 0.24 + 0.04 * math.sin(now * 0.7), cardRy = -0.34 + 0.07 * math.sin(now * 0.5) - d * 0.8;
    final note = _span(t, 0.62, 1, Curves.easeOutBack);
    final bellRx = 0.2, bellRy = 0.4 * math.sin(now * 0.9) - d * 1.2;

    return _stage([
      (
        0,
        Slab(
          size: const Size(256, 178),
          radius: 26,
          depth: 9,
          rx: cardRx,
          ry: cardRy,
          opacity: _span(t, 0, 0.35),
          edge: const Color(0xFF2A2218),
          transform: place(Offset(-6, -18 + (1 - _span(t, 0, 0.6)) * 40), rx: cardRx, ry: cardRy),
          face: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF33281A), Color(0xFF14120F)]),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _logoChip('netflix', 22),
                  const SizedBox(width: 8),
                  const Text('Netflix · free trial', style: TextStyle(color: kText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
                const Spacer(),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${7 - elapsed.round()}', style: display(64, color: const Color(0xFFFFC266))),
                  const SizedBox(width: 8),
                  const Text('days left', style: TextStyle(color: kMuted, fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  for (var k = 0; k < 7; k++) ...[
                    if (k > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 6,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(3)),
                        child: FractionallySizedBox(
                          widthFactor: (elapsed - k).clamp(0.0, 1.0),
                          child: Container(decoration: BoxDecoration(color: const Color(0xFFFFC266), borderRadius: BorderRadius.circular(3))),
                        ),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  for (var k = 0; k < 7; k++)
                    Expanded(
                      child: Text(_marks[k] ?? '',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700, color: (k == 0 || elapsed >= k) ? const Color(0xFFFFC266) : kFaint)),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
      (
        -30,
        IconToken(
          size: 70,
          rx: bellRx,
          ry: bellRy,
          icon: CupertinoIcons.bell_fill,
          colors: const [Color(0xFFFFD27A), Color(0xFFFFA63D), Color(0xFFFF7A45)],
          edge: const Color(0xFFB0581F),
          opacity: _span(t, 0.2, 0.5),
          transform: place(Offset(118, -128 + 7 * math.sin(now * 1.1)), z: -30, rx: bellRx, ry: bellRy,
              scale: 0.5 + 0.5 * _span(t, 0.2, 0.6, Curves.easeOutBack)),
        ),
      ),
      (
        -80,
        Slab(
          size: const Size(276, 78),
          radius: 22,
          depth: 6,
          rx: 0.14,
          ry: -0.12 - d * 0.5,
          opacity: _span(t, 0.62, 0.8),
          transform: place(Offset(14, 120 - (1 - note) * 40), z: -80, rx: 0.14, ry: -0.12 - d * 0.5, scale: 0.85 + 0.15 * note),
          face: DecoratedBox(
            decoration: _glass,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                const AppLogo(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Text('Subtracker', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
                      Spacer(),
                      Text('now', style: caption),
                    ]),
                    const SizedBox(height: 2),
                    const Text('Netflix trial ends in 3 days', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kText)),
                    Text('Then £10.99 a month. Cancel now if you won\'t use it.', maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Page 3: charges drop onto an account card, overflow its balance, and the alert lands.
class _ShortfallScene extends StatelessWidget {
  const _ShortfallScene({required this.t, required this.d, required this.now});
  final double t, d, now;

  static const _balance = 42.67;
  static const _charges = [35.00, 11.99, 10.99, 8.99]; // 66.97 due → £24.30 short
  static const _coins = [('klarna', '−£35.00'), ('spotify', '−£11.99'), ('netflix', '−£10.99'), ('notion', '−£8.99')];

  @override
  Widget build(BuildContext context) {
    final cardRx = 0.5 + 0.04 * math.sin(now * 0.6), cardRy = -0.22 + 0.06 * math.sin(now * 0.45) - d * 0.8;
    final fill = _span(t, 0.3, 0.85);
    final alert = _span(t, 0.72, 1, Curves.easeOutBack);
    final nodes = <_Node>[
      (
        0,
        Slab(
          size: const Size(268, 168),
          radius: 22,
          depth: 7,
          rx: cardRx,
          ry: cardRy,
          edge: const Color(0xFF2A1A22),
          gloss: 0.32,
          opacity: _span(t, 0, 0.35),
          transform: place(Offset(0, 4 + (1 - _span(t, 0, 0.6)) * 40), rx: cardRx, ry: cardRy),
          face: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A1E2A), Color(0xFF16121A), Color(0xFF0E0F14)]),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // Chip.
                  Container(
                    width: 30,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(colors: [Color(0xFFE9D3A0), Color(0xFFB8955A)]),
                    ),
                  ),
                  const Spacer(),
                  const Text('Everyday  ••4821', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                ]),
                const Spacer(),
                const Text('Balance', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                BigMoney(_balance, 'GBP', size: 30),
                const SizedBox(height: 10),
                SizedBox(height: 14, width: double.infinity, child: CustomPaint(painter: _BarPainter(fill))),
                const SizedBox(height: 6),
                Row(children: [
                  const Text('Due by Thursday', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('£66.97', style: TextStyle(color: kText, fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ];

    for (var k = 0; k < _coins.length; k++) {
      final p = _span(t, 0.12 + 0.11 * k, 0.5 + 0.11 * k, Curves.easeOutBack);
      final x = -114 + 76.0 * k;
      final y = -138 + (k.isOdd ? -14 : 0) + 5 * math.sin(now * 1.3 + k);
      final ry = 0.35 * math.sin(now * 1.1 + k * 1.7) - d;
      const rx = 0.25;
      final z = -10.0 - 12 * k;
      final fade = _span(t, 0.12 + 0.11 * k, 0.3 + 0.11 * k);
      final yy = y - (1 - p) * 220;
      nodes.add((z, _iconSlab(_coins[k].$1, m: place(Offset(x, yy), z: z, rx: rx, ry: ry), rx: rx, ry: ry, size: 58, opacity: fade)));
      nodes.add((z - 0.1, _pricePill(_coins[k].$2, place(Offset(x, yy + 42), z: z), fade)));
    }

    nodes.add((
      -90,
      Slab(
        size: const Size(250, 66),
        radius: 22,
        depth: 6,
        rx: 0.16,
        ry: -d * 0.5,
        opacity: _span(t, 0.72, 0.85),
        transform: place(Offset(0, 132 - (1 - alert) * 36), z: -90, rx: 0.16, ry: -d * 0.5, scale: 0.85 + 0.15 * alert),
        face: DecoratedBox(
          decoration: _glass,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: kCrimson.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: const Icon(CupertinoIcons.arrow_down_right, color: kCrimson, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('£24.30 short', style: display(17, color: kCrimson)),
                  const Text('Top up before Thursday', style: caption),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ));
    return _stage(nodes);
  }
}

/// Charges filling past the balance marker; the overflow turns red.
class _BarPainter extends CustomPainter {
  _BarPainter(this.fill);
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final charges = _ShortfallScene._charges;
    final total = charges.fold(0.0, (s, c) => s + c);
    final mark = size.width * _ShortfallScene._balance / total;
    final bar = Rect.fromLTWH(0, (size.height - 8) / 2, size.width, 8);
    final r = RRect.fromRectAndRadius(bar, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.10));

    canvas.save();
    canvas.clipRRect(r);
    final end = size.width * fill;
    canvas.drawRect(Rect.fromLTRB(0, bar.top, end.clamp(0, mark), bar.bottom), Paint()..color = kText);
    if (end > mark) canvas.drawRect(Rect.fromLTRB(mark, bar.top, end, bar.bottom), Paint()..color = kCrimson);
    var x = 0.0;
    for (final c in charges.take(charges.length - 1)) {
      x += size.width * c / total;
      if (x < end) canvas.drawRect(Rect.fromLTWH(x - 1, bar.top, 2, bar.height), Paint()..color = const Color(0xFF16121A));
    }
    canvas.restore();

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(mark - 1, 0, 2, size.height), const Radius.circular(1)), Paint()..color = kText);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.fill != fill;
}
