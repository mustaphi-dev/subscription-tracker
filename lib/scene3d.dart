import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ui.dart';

// ───────── Lightweight 3D for the brand moments ─────────
// Everything here is drawn with Flutter transforms and gradients: no image, video or
// Lottie assets, so it stays crisp at any size, weighs nothing, and can be scrubbed
// frame-by-frame by a gesture. Coordinates are logical pixels around the centre of the
// enclosing Stack; +z points away from the viewer.

/// Perspective strength shared by every scene so objects agree on depth.
const kPerspective = 0.0016;

/// Full transform for an object at [pos], rotated by [rx]/[ry]/[rz] (radians) and [scale]d.
Matrix4 place(Offset pos, {double z = 0, double rx = 0, double ry = 0, double rz = 0, double scale = 1}) => Matrix4.identity()
  ..setEntry(3, 2, kPerspective)
  ..translateByDouble(pos.dx, pos.dy, z, 1)
  ..rotateX(rx)
  ..rotateY(ry)
  ..rotateZ(rz)
  ..scaleByDouble(scale, scale, scale, 1);

/// A seconds counter that ticks while mounted. Frozen at 0 when the platform asks for reduced motion.
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

/// An extruded rounded slab (card, tile, coin) with real thickness, edge shading and a
/// specular band that slides with the tilt, the way light catches a physical card.
class Slab extends StatelessWidget {
  const Slab({
    super.key,
    required this.size,
    required this.transform,
    required this.face,
    this.rx = 0,
    this.ry = 0,
    this.radius = 20,
    this.depth = 8,
    this.edge = const Color(0xFF1A1D25),
    this.gloss = 0.28,
    this.opacity = 1,
  });

  final Size size;

  /// Full placement, usually from [place]. [rx]/[ry] repeat the tilt so the shine can follow it.
  final Matrix4 transform;
  final double rx, ry;
  final Widget face;
  final double radius, depth, gloss, opacity;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0.01) return const SizedBox.shrink();
    final layers = (depth / 1.5).ceil().clamp(1, 14);
    final shape = BorderRadius.circular(radius);
    // Where the highlight sits across the face (0 = top-left, 1 = bottom-right).
    final s = (0.45 - ry * 0.85 + rx * 0.5).clamp(-0.2, 1.2);
    double c(double v) => v.clamp(0.0, 1.0);

    Widget layer(double dz, Widget child) => Transform(
          transform: transform.clone()..translateByDouble(0, 0, dz, 1),
          alignment: Alignment.center,
          child: SizedBox.fromSize(size: size, child: child),
        );

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        // Side walls: stacked layers from the back, darkening with depth.
        for (var k = layers; k >= 1; k--)
          layer(
            depth * k / layers,
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                color: Color.lerp(edge, Colors.black, 0.45 * k / layers),
                boxShadow: k == layers
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 28))]
                    : null,
              ),
            ),
          ),
        layer(
          0,
          ClipRRect(
            borderRadius: shape,
            child: Stack(fit: StackFit.expand, children: [
              face,
              // Specular sweep.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: gloss), Colors.white.withValues(alpha: 0)],
                      stops: [c(s - 0.22), c(s), c(s + 0.22)],
                    ),
                  ),
                ),
              ),
              // Bevel: a hairline that's bright on the lit top edge.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A thick, glossy 3D token carrying an icon. Defaults to the app mark.
class IconToken extends StatelessWidget {
  const IconToken({
    super.key,
    required this.transform,
    this.size = 96,
    this.rx = 0,
    this.ry = 0,
    this.opacity = 1,
    this.icon = CupertinoIcons.arrow_2_circlepath,
    this.colors = const [Color(0xFF4A82FF), Color(0xFF2F6BFF), Color(0xFF8A5CFF)],
    this.edge = const Color(0xFF3A2FB0),
    this.iconColor = Colors.white,
  });
  final Matrix4 transform;
  final double size, rx, ry, opacity;
  final IconData icon;
  final List<Color> colors;
  final Color edge, iconColor;

  @override
  Widget build(BuildContext context) => Slab(
        size: Size.square(size),
        transform: transform,
        rx: rx,
        ry: ry,
        radius: size * 0.28,
        depth: size * 0.16,
        edge: edge,
        gloss: 0.38,
        opacity: opacity,
        face: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          ),
          child: Icon(icon, size: size * 0.55, color: iconColor),
        ),
      );
}

/// Slow-moving coloured light behind a scene, with drifting motes and a fade to the page
/// colour at the bottom so text stays readable. [colors] can change every frame (it's
/// interpolated while swiping between onboarding pages).
class Aurora extends StatelessWidget {
  const Aurora({super.key, required this.clock, required this.colors, this.intensity = 1, this.focus = const Alignment(0, -0.35)});
  final ValueListenable<double> clock;
  final List<Color> colors;
  final double intensity;
  final Alignment focus;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _AuroraPainter(clock, colors, intensity, focus), size: Size.infinite),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.clock, this.colors, this.intensity, this.focus) : super(repaint: clock);
  final ValueListenable<double> clock;
  final List<Color> colors;
  final double intensity;
  final Alignment focus;

  static final _motes = List.generate(36, (i) {
    final r = math.Random(i * 7919 + 13);
    return (r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.6, r.nextDouble() * math.pi * 2, 0.15 + r.nextDouble() * 0.35);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = kBg);
    if (intensity <= 0) return;
    final c = focus.alongSize(size);

    for (var i = 0; i < colors.length; i++) {
      final ph = i * 2.1;
      final center = c +
          Offset(
            w * 0.28 * math.sin(t * 0.21 + ph),
            h * 0.10 * math.cos(t * 0.17 + ph * 1.3) + (i - 1) * h * 0.05,
          );
      final r = w * (0.85 + 0.12 * math.sin(t * 0.3 + ph));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [
            colors[i].withValues(alpha: 0.42 * intensity),
            colors[i].withValues(alpha: 0.12 * intensity),
            colors[i].withValues(alpha: 0),
          ], stops: const [0, 0.45, 1])
              .createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // Motes rising slowly through the light.
    final mote = Paint();
    for (final (x, y, sz, ph, speed) in _motes) {
      final yy = (y - t * speed * 0.03) % 1.0;
      final a = (0.5 + 0.5 * math.sin(t * 1.3 + ph)) * intensity * (1 - yy * 0.6) * 0.5;
      mote.color = Colors.white.withValues(alpha: a.clamp(0, 1));
      canvas.drawCircle(Offset(x * w, yy * h * 0.75), sz, mote);
    }

    // Fade into the page.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBg.withValues(alpha: 0), kBg.withValues(alpha: 0), kBg],
          stops: const [0, 0.5, 0.82],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.intensity != intensity || !listEquals(o.colors, colors) || o.focus != focus;
}

/// A tilted orbit drawn in perspective around the scene centre. Paint it twice, once with
/// [front] false behind the subject and once with [front] true in front of it, so the
/// ring and its satellites pass behind and in front.
class OrbitRing extends CustomPainter {
  OrbitRing({
    required this.radius,
    required this.tilt,
    required this.spin,
    required this.front,
    this.progress = 1,
    this.satellites = const [],
    this.color = Colors.white,
    this.xScale = 1,
  });
  final double radius, tilt, spin, progress;

  /// Squash the orbit horizontally (1 = circle) so it fits narrow stages.
  final double xScale;
  final bool front;
  final List<Color> satellites;
  final Color color;

  (Offset, double) _project(double a) {
    final x = radius * xScale * math.cos(a), z0 = radius * math.sin(a);
    final y = -z0 * math.sin(tilt), z = z0 * math.cos(tilt);
    final w = 1 + kPerspective * z;
    return (Offset(x / w, y / w), z);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const steps = 160;
    final sweep = math.pi * 2 * progress;
    for (var k = 0; k < steps; k++) {
      final a0 = spin + sweep * k / steps, a1 = spin + sweep * (k + 1) / steps;
      final (p0, z0) = _project(a0);
      final (p1, _) = _project(a1);
      if ((z0 < 0) != front) continue;
      // Brighter nearer the viewer.
      stroke.color = color.withValues(alpha: (0.16 + 0.22 * (-z0 / radius).clamp(0, 1)));
      canvas.drawLine(c + p0, c + p1, stroke);
    }
    for (var i = 0; i < satellites.length; i++) {
      final a = spin * 1.6 + i * math.pi * 2 / satellites.length;
      if ((a - spin) % (math.pi * 2) > sweep) continue;
      final (p, z) = _project(a);
      if ((z < 0) != front) continue;
      final s = 4.5 / (1 + kPerspective * z);
      canvas.drawCircle(c + p, s * 3, Paint()..color = satellites[i].withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(c + p, s, Paint()..color = satellites[i]);
    }
  }

  @override
  bool shouldRepaint(OrbitRing o) => o.spin != spin || o.progress != progress || o.tilt != tilt || o.front != front;
}
