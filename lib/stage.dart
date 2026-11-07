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

/// The bare stage, filling its parent.
class StagePlate extends StatelessWidget {
  const StagePlate({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: kBg,
    child: _staged(const Image(image: AssetImage(kStagePlate), fit: BoxFit.cover, gaplessPlayback: true)),
  );
}

/// A seamless, muted loop for a scene on the stage.
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
