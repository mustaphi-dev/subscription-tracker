import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'brand_mark.dart';
import 'stage.dart';
import 'ui.dart';

/// Has this device seen onboarding? Loaded before runApp so the router can redirect synchronously.
final onboarded = ValueNotifier(false);
const _storage = FlutterSecureStorage();

/// Run with `--dart-define=REPLAY_ONBOARDING=true` to forget it on every launch, so the
/// story can be tested again. Uninstalling isn't enough on iOS: the keychain keeps it.
Future<void> loadOnboarded() async {
  if (const bool.fromEnvironment('REPLAY_ONBOARDING')) await _storage.delete(key: 'onboarded');
  onboarded.value = await _storage.read(key: 'onboarded') == 'yes';
}

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

// ───────── Splash ─────────

/// Set as the splash starts to leave, so the first onboarding scene begins its loop
/// from the top as it is revealed instead of partway through (the hourglass mid-flip).
final splashGone = ValueNotifier<bool>(false);

/// Cold-start brand moment layered over the app. The native launch screen is only the
/// background colour. The middle of the W rises out of the dark, the two cut legs slide
/// down their slant into place and the mark flinches as they land (the wince), a sheen
/// crosses the face, the wordmark writes itself in underneath, and everything dissolves
/// into the app. Tap to skip; reduced motion shows the finished mark and fades.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key});
  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  static const _length = Duration(milliseconds: 2500);

  /// Fraction of the intro at which the W is whole (the legs land and it flinches).
  static const _traced = 0.6;

  late final _intro = AnimationController(vsync: this, duration: _length);
  late final _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _started = false, _leaving = false, _gone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Start once the W is decoded (or after a beat regardless), so it never pops in late.
    var begun = false;
    void begin() {
      if (begun || !mounted) return;
      begun = true;
      if (reduced) {
        _intro.value = 1;
        Future.delayed(const Duration(milliseconds: 700), _leave);
        return;
      }
      _intro.forward().then((_) => _leave());
      Future.delayed(_length * _traced, () {
        if (mounted && !_leaving) HapticFeedback.lightImpact();
      });
    }

    Future.wait([for (final a in kMarkLayers) precacheImage(AssetImage(a), context)]).whenComplete(begin);
    Future.delayed(const Duration(milliseconds: 600), begin);
  }

  void _leave() {
    if (!mounted || _leaving) return;
    _leaving = true;
    splashGone.value = true;
    _intro.stop();
    _exit.forward().then((_) {
      if (mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _exit]),
      builder: (context, _) {
        final t = _intro.value, e = Curves.easeInCubic.transform(_exit.value);
        final size = math.min(MediaQuery.sizeOf(context).width * 0.5, 210.0);

        final middle = _span(t, 0.04, 0.36);                                 // the middle of the W rises
        final legs = _span(t, 0.26, _traced, Curves.easeInCubic);            // the cut legs slide in and land
        final flinch = 1 - (2 * (t - _traced) / 0.16).abs().clamp(0.0, 1.0); // a quick squeeze on landing
        final glow = _span(t, 0.2, _traced + 0.25);
        final lift = _span(t, _traced, 0.9, Curves.easeInOutCubic);
        final shift = Offset(0, -26 * lift);

        const word = 'Wince';
        final w0 = _traced + 0.02;
        final wordIn = _span(t, w0, w0 + 0.34);

        return IgnorePointer(
          ignoring: _leaving,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _leave,
            child: Opacity(
              opacity: 1 - e,
              child: ColoredBox(
                color: kBg,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Soft light pooling behind the W.
                    Center(
                      child: Transform.translate(
                        offset: shift,
                        child: Container(
                          width: size * 2.8,
                          height: size * 2.8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFFFFFFF).withValues(alpha: 0.10 * glow),
                                const Color(0xFFB8B8C8).withValues(alpha: 0.03 * glow),
                                const Color(0xFFB8B8C8).withValues(alpha: 0),
                              ],
                              stops: const [0, 0.4, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Transform.translate(
                        offset: shift,
                        child: Transform.scale(
                          scale: (0.96 + 0.04 * Curves.easeOutCubic.transform(middle)) * (1 + 0.18 * e),
                          child: BrandMark(
                            size: size,
                            middle: middle,
                            legs: legs,
                            flinch: flinch,
                            sheen: _span(t, _traced - 0.06, _traced + 0.3, Curves.easeInOut),
                          ),
                        ),
                      ),
                    ),
                    // Wordmark: each letter fades up in turn, the word settling as it completes.
                    Center(
                      child: Transform.translate(
                        offset: shift + Offset(0, size / 2 + 34 + 10 * (1 - wordIn)),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              for (var i = 0; i < word.length; i++)
                                TextSpan(
                                  text: word[i],
                                  style: TextStyle(color: Colors.white.withValues(alpha: _span(t, w0 + 0.022 * i, w0 + 0.022 * i + 0.14))),
                                ),
                            ],
                          ),
                          // The splash sits above the navigator, outside any Material, so the
                          // underline of the fallback text style has to be cleared here.
                          style: display(30, weight: FontWeight.w600).copyWith(letterSpacing: -0.9 + 2.4 * (1 - wordIn), decoration: TextDecoration.none),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────── Onboarding ─────────
// A three-beat story about the feeling the app is named after. A free trial starts
// (the hourglass, time quietly running), it renews while you're not looking (the loop
// that never stops), and one day it takes your last penny (the coin with a slice
// missing). The last page lands with a flinch, the wince, and the sign-in screen
// answers it. Every page shares one stage (stage.dart), so swiping only changes the
// object on it and the words under it.

class _Page {
  const _Page(this.name, this.title, this.body, {this.drop = 0});
  final String name, title, body;

  /// How far the object sits below the stage's usual spot, as a fraction of its height.
  final double drop;

  /// First frame of the loop, shown instantly and whenever video can't play.
  String get still => 'assets/onboarding/$name.jpg';

  /// Seamless loop that starts and ends on [still].
  String get video => 'assets/onboarding/$name.mp4';
}

const _pagesData = [
  _Page('trials', 'It started with\na free trial.', 'Seven days, no charge. You\'d cancel in time.', drop: 0.06),
  _Page('renewals', 'Then it quietly\nrenewed.', 'And again next month. And the one after that.'),
  _Page('shortfalls', 'Until it took\nyour last penny.', 'That feeling has a name.'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  int _page = 0;
  bool _prepared = false, _still = false;

  /// The wince: a short, damped shudder when the story reaches the last penny.
  late final _flinch = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  bool _flinched = false;

  /// One muted looping player per page; only the visible page plays.
  late final _videos = [for (final p in _pagesData) stageVideo(p.video, play: false)];

  @override
  void initState() {
    super.initState();
    for (final v in _videos) {
      v.addListener(_syncOnReady);
    }
    splashGone.addListener(_syncPlayback);
  }

  /// Starts the visible page's loop once its player is ready and the splash has gone.
  void _syncOnReady() {
    if (_videos.every((v) => v.value.isInitialized)) {
      for (final v in _videos) {
        v.removeListener(_syncOnReady);
      }
    }
    _syncPlayback();
  }

  void _syncPlayback() {
    if (!mounted) return;
    for (var i = 0; i < _videos.length; i++) {
      final v = _videos[i];
      if (!v.value.isInitialized) continue;
      final want = i == _page && !_still && splashGone.value;
      if (want && !v.value.isPlaying) {
        v.play();
      } else if (!want && v.value.isPlaying) {
        v.pause();
      }
    }
  }

  bool get _last => _page == _pagesData.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;
    precacheImage(const AssetImage(kStagePlate), context);
    for (final p in _pagesData) {
      precacheImage(AssetImage(p.still), context);
    }
    _still = MediaQuery.disableAnimationsOf(context);
  }

  void _maybeFlinch() {
    if (!_last || _flinched) return;
    _flinched = true;
    Future.delayed(const Duration(milliseconds: 380), () {
      if (!mounted || !_last) return;
      HapticFeedback.heavyImpact();
      if (!_still) _flinch.forward(from: 0);
    });
  }

  /// Horizontal shudder and squeeze from [_flinch]: a few fast, decaying swings.
  ({double dx, double squeeze}) get _shudder {
    final f = _flinch.value;
    if (f == 0 || f == 1) return (dx: 0, squeeze: 1);
    final decay = math.pow(1 - f, 2).toDouble();
    return (dx: math.sin(f * math.pi * 7) * 9 * decay, squeeze: 1 - 0.035 * math.sin(math.min(f * 3, 1) * math.pi));
  }

  @override
  void dispose() {
    splashGone.removeListener(_syncPlayback);
    _flinch.dispose();
    _pages.dispose();
    for (final v in _videos) {
      v
        ..removeListener(_syncOnReady)
        ..dispose();
    }
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
        animation: Listenable.merge([_pages, _flinch]),
        builder: (context, _) {
          final pos = _pages.hasClients && _pages.position.haveDimensions ? _pages.page ?? 0 : _page.toDouble();
          final shudder = _shudder;
          final lastIndex = _pagesData.length - 1;

          return Stack(
            fit: StackFit.expand,
            children: [
              const StagePlate(),
              // Scenes: the one being left dissolves into the one arriving, on the same stage.
              for (var i = 0; i < _pagesData.length; i++)
                if ((pos - i).abs() < 1)
                  Opacity(
                    opacity: (1 - (pos - i).abs()).clamp(0.0, 1.0) * _span(intro, 0, 0.5),
                    child: Transform.translate(
                      offset: Offset(i == lastIndex ? shudder.dx * 1.6 : 0, 0),
                      child: Transform.scale(
                        scale: 1.03 - 0.03 * _span(intro, 0, 1),
                        child: StageScene(still: _pagesData[i].still, video: _videos[i], drop: _pagesData[i].drop),
                      ),
                    ),
                  ),
              // Scrim so the type always reads, even on short phones.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [kBg.withValues(alpha: 0), kBg.withValues(alpha: 0), kBg.withValues(alpha: 0.8), kBg],
                      stops: const [0, 0.5, 0.74, 1],
                    ),
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
                        onPageChanged: (i) {
                          setState(() => _page = i);
                          _syncPlayback();
                          _maybeFlinch();
                        },
                        itemBuilder: (_, i) {
                          final t = (1 - (pos - i).abs()).clamp(0.0, 1.0) * intro;
                          final page = _pagesData[i];
                          final lines = page.title.split('\n');
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                              child: Transform.translate(
                                offset: Offset(i == lastIndex ? shudder.dx : 0, 0),
                                child: Transform.scale(
                                  scale: i == lastIndex ? shudder.squeeze : 1,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ShaderMask(
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
                                                  style: display(42, weight: FontWeight.w500).copyWith(height: 1.08, letterSpacing: -1.7),
                                                ),
                                                dy: 22,
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      _rise(
                                        _span(t, 0.55, 1),
                                        Text(
                                          page.body,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: kText.withValues(alpha: 0.58), fontSize: 15.5, height: 1.4, letterSpacing: -0.1),
                                        ),
                                        dy: 12,
                                      ),
                                    ],
                                  ),
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
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              overlayColor: Colors.black,
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(_last ? 'Never again' : 'Continue', key: ValueKey(_last)),
                            ),
                          ),
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(2)),
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
