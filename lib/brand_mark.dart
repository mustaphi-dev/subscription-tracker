import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'brand_mark_path.dart';

/// The chrome S (rendered in Blender, without its light) that the splash animates.
const kMarkAsset = 'assets/brand/mark.webp';

/// Violet light running along the groove of the chrome S, drawn over [kMarkAsset] at
/// the same size. [head] is how far along the groove the light has got (0 = top
/// terminal, 1 = bottom terminal; values past 1 let the tail run out), [tail] is the
/// length of its trail as a fraction of the groove, and [settle] (0–1) fills the whole
/// groove with a soft resting glow, as on the app icon.
class MarkLightPainter extends CustomPainter {
  MarkLightPainter({required this.head, this.tail = 0.4, this.settle = 0, this.opacity = 1});
  final double head, tail, settle, opacity;

  static const _deep = Color(0xFF5B2BFF), _hot = Color(0xFFD9CFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    // Every other sample of the groove is plenty at splash size and halves the draw calls.
    final pts = [
      for (var i = 0; i < kMarkGroove.length; i += 2) Offset(kMarkGroove[i].dx * size.width, kMarkGroove[i].dy * size.height),
      if (kMarkGroove.length.isEven) Offset(kMarkGroove.last.dx * size.width, kMarkGroove.last.dy * size.height),
    ];
    final n = pts.length - 1;
    final groove = kMarkGrooveWidth * size.width;

    // Intensity per segment: a comet (bright head, fading tail) plus the resting glow
    // that grows in behind it as it settles.
    double at(double u) {
      final x = head - u; // distance behind the head
      final comet = x < 0 ? 0.0 : math.pow((1 - x / tail).clamp(0.0, 1.0), 1.6).toDouble();
      final spark = x < 0 ? 0.0 : math.exp(-x * 90);
      final rest = settle * (0.35 + 0.25 * math.sin(math.pi * u));
      return math.min(1.0, comet + spark + rest) * opacity;
    }

    final lit = [for (var k = 0; k < n; k++) at((k + 0.5) / n)];
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Halo: the lit segments drawn wide into one layer that is blurred once.
    final bounds = Offset.zero & size;
    canvas.saveLayer(
      bounds.inflate(groove * 8),
      Paint()
        ..blendMode = BlendMode.plus
        ..imageFilter = ImageFilter.blur(sigmaX: groove * 2.2, sigmaY: groove * 2.2),
    );
    stroke.strokeWidth = groove * 3.2;
    for (var k = 0; k < n; k++) {
      if (lit[k] < 0.01) continue;
      stroke.color = _deep.withValues(alpha: 0.55 * lit[k]);
      canvas.drawLine(pts[k], pts[k + 1], stroke);
    }
    canvas.restore();

    // Core: the light itself, hotter and wider toward the head.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.plus);
    stroke.strokeCap = StrokeCap.butt; // butt joins: no brighter beads where segments overlap
    for (var k = 0; k < n; k++) {
      final i = lit[k];
      if (i < 0.01) continue;
      stroke
        ..strokeWidth = groove * (0.55 + 0.45 * i)
        ..color = Color.lerp(_deep, _hot, i)!.withValues(alpha: math.min(1.0, 1.2 * i));
      canvas.drawLine(pts[k], pts[k + 1], stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkLightPainter old) =>
      old.head != head || old.tail != tail || old.settle != settle || old.opacity != opacity;
}

/// The chrome S with its light: the still mark at [chrome] opacity, a sheen that sweeps
/// across the metal at [sheen] (0–1, off outside that range) and the groove light.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, this.chrome = 1, this.head = 2, this.tail = 0.4, this.settle = 1, this.sheen = -1});
  final double size, chrome, head, tail, settle, sheen;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(kMarkAsset, width: size, height: size, filterQuality: FilterQuality.medium);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Opacity(opacity: chrome.clamp(0.0, 1.0), child: image),
          if (sheen > 0 && sheen < 1 && chrome > 0)
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) {
                final c = -0.4 + 1.8 * sheen; // band centre travels across, top-left to bottom-right
                return LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
                  stops: [(c - 0.12).clamp(0.0, 1.0), c.clamp(0.0, 1.0), (c + 0.12).clamp(0.0, 1.0)],
                ).createShader(r);
              },
              child: image,
            ),
          CustomPaint(size: Size.square(size), painter: MarkLightPainter(head: head, tail: tail, settle: settle)),
        ],
      ),
    );
  }
}
