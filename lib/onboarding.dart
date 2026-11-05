import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

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
Widget _rise(double r, Widget child, {double dy = 16}) => Opacity(
  opacity: r.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, (1 - r) * dy), child: child),
);

const _brandLight = [Color(0xFF6C4BFF), Color(0xFF2F6BFF), Color(0xFF8B7CFF)];

// ───────── Splash ─────────

/// Cold-start brand moment layered over the app: the mark spins in as a glossy 3D token,
/// the wordmark lands, then the whole thing dissolves into the app.
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
        const word = 'Subtracker';

        return IgnorePointer(
          ignoring: _leaving,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _leave,
            child: Opacity(
              opacity: 1 - e,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Aurora(clock: _clock, colors: _brandLight, intensity: glow, focus: const Alignment(0, -0.2)),
                  Center(
                    child: Transform.scale(
                      scale: 1 + 0.12 * e,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 280,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                IconToken(
                                  size: 96,
                                  rx: rx,
                                  ry: ry,
                                  opacity: _span(t, 0.02, 0.2),
                                  transform: place(Offset(0, -5 * math.sin(now * 1.3) * settled), rx: rx, ry: ry, scale: 0.55 + 0.45 * spin),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var k = 0; k < word.length; k++)
                                _rise(_span(t, 0.38 + 0.025 * k, 0.68 + 0.025 * k), Text(word[k], style: display(34)), dy: 18),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _rise(_span(t, 0.66, 0.96), const Text('Every renewal, before it hits.', style: TextStyle(color: kMuted, fontSize: 15)), dy: 8),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────── Onboarding ─────────
// One cinematic render per page, full bleed, with a single line of big type over it.
// Swiping cross-fades the renders with a little parallax; each render also breathes
// slowly (scale + drift) so the screen never feels like a static poster.

class _Page {
  const _Page(this.image, this.title, this.tone);
  final String image, title;

  /// Darkest colour at the bottom of the render; the text scrim fades into it.
  final Color tone;
}

const _pagesData = [
  _Page('assets/onboarding/renewals.jpg', 'Every renewal,\nbefore it hits.', Color(0xFF0E0D1F)),
  _Page('assets/onboarding/trials.jpg', 'Trials end on\nyour terms.', Color(0xFF290A05)),
  _Page('assets/onboarding/shortfalls.jpg', 'See a shortfall\ncoming.', Color(0xFF1F1213)),
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
  bool _prepared = false;

  bool get _last => _page == _pagesData.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;
    for (final p in _pagesData) {
      precacheImage(AssetImage(p.image), context);
    }
    if (MediaQuery.disableAnimationsOf(context)) _clock.freeze();
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
    _pages.nextPage(duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: TweenAnimationBuilder<double>(
      // One-off entrance; afterwards the page position drives everything.
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      builder: (_, intro, _) => AnimatedBuilder(
        animation: Listenable.merge([_pages, _clock]),
        builder: (context, _) {
          final pos = _pages.hasClients && _pages.position.haveDimensions ? _pages.page ?? 0 : _page.toDouble();
          final now = _clock.value;
          final w = MediaQuery.sizeOf(context).width;
          final i0 = pos.floor().clamp(0, _pagesData.length - 1), i1 = pos.ceil().clamp(0, _pagesData.length - 1);
          final tone = Color.lerp(_pagesData[i0].tone, _pagesData[i1].tone, pos - pos.floor())!;

          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: tone),
              // Renders: the one being left fades out under the one arriving.
              for (var i = 0; i < _pagesData.length; i++)
                if ((pos - i).abs() < 1)
                  Opacity(
                    opacity: (1 - (pos - i).abs()).clamp(0.0, 1.0) * _span(intro, 0, 0.5),
                    child: Transform.translate(
                      offset: Offset(-(pos - i) * w * 0.35, 36 + 6 * math.sin(now * 0.6 + i)),
                      child: Transform.scale(
                        alignment: const Alignment(0, -0.4),
                        scale: 1.08 + 0.02 * math.sin(now * 0.35 + i * 2) + 0.06 * (1 - _span(intro, 0, 1)) + 0.05 * (pos - i).abs(),
                        // Full width so the whole composition shows; the bottom melts into the page tone.
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (r) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white, Colors.white, Colors.transparent],
                              stops: [0, 0.8, 1],
                            ).createShader(r),
                            child: Image.asset(_pagesData[i].image, width: w, fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
                          ),
                        ),
                      ),
                    ),
                  ),
              // Scrim so the type always reads.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tone.withValues(alpha: 0.35), tone.withValues(alpha: 0), tone.withValues(alpha: 0), tone.withValues(alpha: 0.85), tone],
                    stops: const [0, 0.14, 0.5, 0.78, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                      child: Opacity(
                        opacity: _span(intro, 0.3, 0.8),
                        child: _Progress(pos: pos, count: _pagesData.length),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _pagesData.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) {
                          final t = (1 - (pos - i).abs()).clamp(0.0, 1.0) * intro;
                          final lines = _pagesData[i].title.split('\n');
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                              child: ShaderMask(
                                // Bright at the top, melting into the scene at the bottom.
                                shaderCallback: (r) => LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.white, Colors.white.withValues(alpha: 0.62)],
                                ).createShader(r),
                                blendMode: BlendMode.modulate,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var k = 0; k < lines.length; k++)
                                      _rise(
                                        _span(t, 0.25 + 0.12 * k, 0.85 + 0.12 * k),
                                        Text(
                                          lines[k],
                                          textAlign: TextAlign.center,
                                          style: display(44, weight: FontWeight.w500).copyWith(height: 1.08, letterSpacing: -1.8),
                                        ),
                                        dy: 22,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                      child: _rise(
                        _span(intro, 0.45, 1),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 60,
                                child: FilledButton(
                                  onPressed: _done,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  child: const Text('Get started'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ArrowButton(onTap: _next, done: _last),
                          ],
                        ),
                        dy: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Round white "next" button; on the last page it turns into a check and finishes.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.onTap, required this.done});
  final VoidCallback onTap;
  final bool done;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: done ? 'Finish' : 'Next',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => ScaleTransition(
            scale: a,
            child: FadeTransition(opacity: a, child: c),
          ),
          child: Icon(done ? CupertinoIcons.checkmark : CupertinoIcons.arrow_right, key: ValueKey(done), color: Colors.black, size: 22),
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
  Widget build(BuildContext context) => Row(
    children: [
      for (var k = 0; k < count; k++) ...[
        if (k > 0) const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 3,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (pos - k + 1).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
