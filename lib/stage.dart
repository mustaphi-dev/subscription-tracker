import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'ui.dart';

// ───────── The Wince stage ─────────
// One backdrop under every onboarding page and the sign-in screens: violet light from
// the top left falling into the app's background colour, with faint isometric blocks
// (tool/art/stage.py). The plate and every 3D loop are 960×1280 and drawn the same way,
// full width and top aligned, so the backdrop never moves as scenes change; only the
// object on it does. Below the plate the page continues in [kBg].

const kStagePlate = 'assets/onboarding/stage.jpg';
const kStageAspect = 960 / 1280;

/// Plate and scenes are drawn a little larger than the screen width, from the top
/// centre, so the object sits lower and bigger; the sides crop evenly.
const kStageZoom = 1.12;

Widget _staged(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: AspectRatio(
    aspectRatio: kStageAspect,
    child: Transform.scale(scale: kStageZoom, alignment: Alignment.topCenter, child: child),
  ),
);

class StagePlate extends StatelessWidget {
  const StagePlate({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: kBg,
    child: _staged(const Image(image: AssetImage(kStagePlate), fit: BoxFit.cover, gaplessPlayback: true)),
  );
}

VideoPlayerController stageVideo(String asset, {bool play = true}) {
  final v = VideoPlayerController.asset(asset, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
  v
    ..setLooping(true)
    ..setVolume(0)
    ..initialize().then((_) {
      if (play) v.play();
    }, onError: (_) {}); // the still stays on failure
  return v;
}

/// A 3D scene on the stage, positioned exactly over [StagePlate]: its first frame as a
/// still, with the loop faded in over it once frames are actually flowing.
class StageScene extends StatelessWidget {
  const StageScene({super.key, required this.still, this.video, this.drop = 0});
  final String still;
  final VideoPlayerController? video;

  /// Moves the scene down by this fraction of the stage's height. Its top edge fades
  /// out so the plate behind shows through without a seam.
  final double drop;

  @override
  Widget build(BuildContext context) => _staged(_dropped(
    Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(still, fit: BoxFit.cover, gaplessPlayback: true),
        if (video case final v?)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: v,
            builder: (_, value, _) {
              final live = value.isInitialized && value.isPlaying && value.position > Duration.zero;
              return AnimatedOpacity(
                opacity: live ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: value.isInitialized
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox.fromSize(size: value.size, child: VideoPlayer(v)),
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
      ],
    ),
  ));

  Widget _dropped(Widget scene) => drop == 0
      ? scene
      : FractionalTranslation(
          translation: Offset(0, drop),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.transparent, Colors.black],
              stops: [0, drop * 2.5],
            ).createShader(r),
            child: scene,
          ),
        );
}

/// A [StageScene] that owns its loop: made once reduced motion is known (a still when it's on), disposed with it.
class LoopScene extends StatefulWidget {
  const LoopScene({super.key, required this.still, required this.video});
  final String still, video;
  @override
  State<LoopScene> createState() => _LoopSceneState();
}

class _LoopSceneState extends State<LoopScene> {
  VideoPlayerController? _video;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _video ??= stageVideo(widget.video, play: !MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StageScene(still: widget.still, video: _video);
}

/// Fades the bottom of the stage into [kBg], from [from] to [to] down the screen, so the type reads.
class StageScrim extends StatelessWidget {
  const StageScrim({super.key, this.from = 0.45, this.to = 0.68, this.alpha = 0.75});
  final double from, to, alpha;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBg.withValues(alpha: 0), kBg.withValues(alpha: 0), kBg.withValues(alpha: alpha), kBg],
          stops: [0, from, to, 1],
        ),
      ),
    ),
  );
}

double span(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Fade + rise driven by [r] (0 hidden, 1 in place).
Widget rise(double r, Widget child, {double dy = 16}) => Opacity(
  opacity: r.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, (1 - r) * dy), child: child),
);
