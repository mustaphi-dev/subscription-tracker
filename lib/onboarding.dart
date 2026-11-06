import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'brand_mark.dart';
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

// ───────── Splash ─────────

/// Cold-start brand moment layered over the app. The native launch screen is only the
/// background colour. A violet light traces an S out of the dark, the chrome S (the app
/// icon's mark) materialises around it with the light settling into its groove, a sheen
/// crosses the metal, the wordmark writes itself in underneath, and everything dissolves
/// into the app. Tap to skip; reduced motion shows the finished mark and fades.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key});
  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  static const _length = Duration(milliseconds: 2500);

  /// Fraction of the intro at which the chrome S has fully appeared.
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
    // Start once the chrome S is decoded (or after a beat regardless), so it never pops in late.
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

    precacheImage(const AssetImage(kMarkAsset), context).whenComplete(begin);
    Future.delayed(const Duration(milliseconds: 600), begin);
  }

  void _leave() {
    if (!mounted || _leaving) return;
    _leaving = true;
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

        final run = _span(t, 0.03, 0.46, Curves.easeInOutCubic);            // light traces the S
        final settle = _span(t, 0.3, _traced);                              // ...and stays lit
        final rise = _span(t, 0.32, _traced);                               // chrome materialises round it
        final glow = _span(t, 0.4, _traced + 0.25);
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
                    // Violet light pooling behind the S once it is lit.
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
                                const Color(0xFF7B4DFF).withValues(alpha: 0.28 * glow),
                                const Color(0xFF4B2BD6).withValues(alpha: 0.08 * glow),
                                const Color(0xFF4B2BD6).withValues(alpha: 0),
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
                          scale: (0.96 + 0.04 * Curves.easeOutCubic.transform(rise)) * (1 + 0.18 * e),
                          child: BrandMark(
                            size: size,
                            chrome: rise,
                            head: run * 1.45,
                            tail: 0.45,
                            settle: settle,
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
                          style: display(30, weight: FontWeight.w600).copyWith(letterSpacing: -0.9 + 2.4 * (1 - wordIn)),
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

/// Seconds since mount, ticking every frame; freeze it for reduced motion.
class SceneClock extends ValueNotifier<double> {
  SceneClock(TickerProvider vsync) : super(0) {
    _ticker = vsync.createTicker((e) => value = e.inMicroseconds / 1e6)..start();
  }
  late final Ticker _ticker;

  void freeze() => _ticker.stop();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

// ───────── Onboarding ─────────
// One cinematic render per page, full bleed, with a single line of big type over it.
// Swiping cross-fades the renders with a little parallax; each render also breathes
// slowly (scale + drift) so the screen never feels like a static poster.

class _Page {
  const _Page(this.name, this.title, this.tone);
  final String name, title;

  /// Darkest colour at the bottom of the render; the text scrim fades into it.
  final Color tone;

  /// First frame of the loop, shown instantly and whenever video can't play.
  String get still => 'assets/onboarding/$name.jpg';

  /// Seamless loop that starts and ends on [still].
  String get video => 'assets/onboarding/$name.mp4';
}

const _pagesData = [
  _Page('renewals', 'Every renewal,\nbefore it hits.', Color(0xFF0B0A15)),
  _Page('trials', 'Trials end on\nyour terms.', Color(0xFF1E0A07)),
  _Page('shortfalls', 'See a shortfall\ncoming.', Color(0xFF160708)),
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
  bool _prepared = false, _still = false;

  /// One muted looping player per page; only the visible page plays.
  final _videos = [for (final p in _pagesData) VideoPlayerController.asset(p.video, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))];

  @override
  void initState() {
    super.initState();
    for (final v in _videos) {
      v
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) => _syncPlayback(), onError: (_) {}); // still image stays on failure
    }
  }

  void _syncPlayback() {
    if (!mounted) return;
    for (var i = 0; i < _videos.length; i++) {
      final v = _videos[i];
      if (!v.value.isInitialized) continue;
      if (i == _page && !_still) {
        v.play();
      } else {
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
    for (final p in _pagesData) {
      precacheImage(AssetImage(p.still), context);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _still = true;
      _clock.freeze();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _clock.dispose();
    for (final v in _videos) {
      v.dispose();
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
                      offset: Offset(-(pos - i) * 0.35 * w, 36 + 6 * math.sin(now * 0.6 + i)),
                      child: Transform.scale(
                        alignment: const Alignment(0, -0.4),
                        scale: (1.08 + 0.02 * math.sin(now * 0.35 + i * 2) + 0.06 * (1 - _span(intro, 0, 1)) + 0.05 * (pos - i).abs()),
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
                            child: Stack(
                              children: [
                                Image.asset(_pagesData[i].still, width: w, fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
                                Positioned.fill(child: _Loop(_videos[i])),
                              ],
                            ),
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
                        onPageChanged: (i) {
                          setState(() => _page = i);
                          _syncPlayback();
                        },
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
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(_last ? 'Get started' : 'Continue', key: ValueKey(_last)),
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

/// The page's video, faded in over the still once frames are actually flowing.
class _Loop extends StatelessWidget {
  const _Loop(this.video);
  final VideoPlayerController video;

  @override
  Widget build(BuildContext context) {
    final v = video.value;
    final live = v.isInitialized && v.isPlaying && v.position > Duration.zero;
    return AnimatedOpacity(
      opacity: live ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      child: v.isInitialized
          ? FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: SizedBox.fromSize(size: v.size, child: VideoPlayer(video)),
            )
          : const SizedBox.shrink(),
    );
  }
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
