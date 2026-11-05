import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The brand mark, drawn live: a two-sided ribbon (lavender one side, violet the other)
/// with one half twist in its middle. It runs along a track like a train: a straight
/// line in, one lap of a circle, a straight line out. When its head has travelled one
/// lap ([closed]) the two ends meet and it is exactly the logo.
///
/// Same maths, shape and view as the icon art and the Blender render, so keep the
/// constants in step with tool/art (make_flat_icons.py, ribbon2.py) if the mark changes.
class Ribbon {
  Ribbon._();

  static const radius = 1.0, width = 0.48, twistSpan = 0.6;
  static const tilt = 58.0, roll = 8.0, yaw = 15.0;
  static const front = Color(0xFFC4B5FF), back = Color(0xFF6236FF);

  /// Ribbon length = one lap; the head position at which the loop closes.
  static const closed = 2 * math.pi * radius;

  static const _n = 220; // segments along the ribbon

  /// Row-major 3×3 view rotation: roll · tilt · yaw (viewer looks down −z).
  static final List<double> _m = () {
    double r(double d) => d * math.pi / 180;
    List<double> mul(List<double> a, List<double> b) => [
      for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++) a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
    ];
    List<double> rz(double a) => [math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a), 0, 0, 0, 1];
    List<double> rx(double a) => [1, 0, 0, 0, math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a)];
    return mul(mul(rz(r(roll)), rx(r(-tilt))), rz(r(yaw)));
  }();

  static double _smooth(double x) {
    x = x.clamp(0.0, 1.0);
    return x * x * x * (x * (6 * x - 15) + 10);
  }

  /// Both edges of the ribbon with its head at [head], projected: (x, y-down, depth)
  /// per sample, left edge then right edge.
  static ({List<Offset> a, List<Offset> b, List<double> za, List<double> zb}) edges(double head) {
    final a = <Offset>[], b = <Offset>[];
    final za = <double>[], zb = <double>[];
    final m = _m;
    for (var k = 0; k <= _n; k++) {
      // 0.4% longer than a lap, so at the join the head tucks over the tail and no
      // anti-aliased hairline shows through.
      final u = -0.5 + k / _n * 1.004;
      final sig = head - closed + (u + 0.5) * closed;
      double cx, cy, nx, ny; // centre and inward normal on the track
      if (sig < 0 || sig > closed) {
        cx = sig < 0 ? -sig : -(sig - closed);
        cy = radius;
        nx = 0;
        ny = -1;
      } else {
        final psi = math.pi / 2 + sig / radius;
        cx = radius * math.cos(psi);
        cy = radius * math.sin(psi);
        nx = -math.cos(psi);
        ny = -math.sin(psi);
      }
      final th = math.pi * _smooth((u + twistSpan / 2) / twistSpan);
      final wx = -nx * math.cos(th), wy = -ny * math.cos(th), wz = math.sin(th);
      for (final s in const [-0.5, 0.5]) {
        final px = cx + s * width * wx, py = cy + s * width * wy, pz = s * width * wz;
        final qx = m[0] * px + m[1] * py + m[2] * pz;
        final qy = m[3] * px + m[4] * py + m[5] * pz;
        final qz = m[6] * px + m[7] * py + m[8] * pz;
        if (s < 0) {
          a.add(Offset(qx, -qy));
          za.add(qz);
        } else {
          b.add(Offset(qx, -qy));
          zb.add(qz);
        }
      }
    }
    return (a: a, b: b, za: za, zb: zb);
  }

  /// Bounds of the closed mark in view units, for framing.
  static final Rect bounds = () {
    final e = edges(closed);
    var r = Rect.fromPoints(e.a.first, e.a.first);
    for (final p in [...e.a, ...e.b]) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }();
}

/// Paints the ribbon with its head at [head] (see [Ribbon.closed]). The closed mark is
/// [extent] logical pixels wide, centred on the canvas plus [shift].
class RibbonPainter extends CustomPainter {
  RibbonPainter({required this.head, required this.extent, this.shift = Offset.zero, this.opacity = 1});
  final double head, extent, opacity;
  final Offset shift;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final scale = extent / Ribbon.bounds.width;
    final origin = size.center(shift) - Ribbon.bounds.center * scale;
    final e = Ribbon.edges(head);
    final n = e.a.length - 1;
    Offset pa(int k) => origin + e.a[k] * scale;
    Offset pb(int k) => origin + e.b[k] * scale;

    // Which side faces us, per segment (sign of the projected quad's area).
    final side = List<bool>.generate(n, (k) {
      final q = [pa(k), pa(k + 1), pb(k + 1), pb(k)];
      var ar = 0.0;
      for (var i = 0; i < 4; i++) {
        ar += q[i].dx * q[(i + 1) % 4].dy - q[(i + 1) % 4].dx * q[i].dy;
      }
      return ar < 0; // y points down: negative area is the lavender side
    });

    // Runs of segments showing the same side, cut short enough to depth-sort, each
    // overlapping the next by a segment so joins never show a hairline.
    final runs = <(int, int, double)>[];
    var s = 0;
    for (var k = 1; k <= n; k++) {
      if (k == n || side[k] != side[s] || k - s >= 36) {
        final end = k < n ? k + 1 : k;
        var z = 0.0;
        for (var i = s; i <= end; i++) {
          z += e.za[i] + e.zb[i];
        }
        runs.add((s, end, z / (2 * (end - s + 1))));
        s = k;
      }
    }
    runs.sort((x, y) => x.$3.compareTo(y.$3));

    final paint = Paint()..isAntiAlias = true;
    for (final (a, b, _) in runs) {
      final path = Path()..moveTo(pa(a).dx, pa(a).dy);
      for (var k = a + 1; k <= b; k++) {
        path.lineTo(pa(k).dx, pa(k).dy);
      }
      for (var k = b; k >= a; k--) {
        path.lineTo(pb(k).dx, pb(k).dy);
      }
      path.close();
      paint.color = (side[a] ? Ribbon.front : Ribbon.back).withValues(alpha: opacity);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(RibbonPainter old) => old.head != head || old.extent != extent || old.shift != shift || old.opacity != opacity;
}

/// Head position for the entrance: glides in from just beyond the left/right edge of
/// a [size] canvas and settles, decelerating, into the closed loop at [t] = 1.
double ribbonEntrance(double t, Size size, double extent, {Offset shift = Offset.zero}) {
  if (t >= 1) return Ribbon.closed;
  final key = (size, extent, shift);
  final p0 = _entryCache.key == key ? _entryCache.p0 : _entryStart(size, extent, shift);
  _entryCache = (key: key, p0: p0);
  final d = Ribbon.closed - p0;
  final s = t.clamp(0.0, 1.0);
  // Hermite from p0 (speed 1.25·d) to closed (speed 0): monotone, eases into the join.
  return p0 + d * (1.25 * (s * s * s - 2 * s * s + s) + (-2 * s * s * s + 3 * s * s));
}

({(Size, double, Offset)? key, double p0}) _entryCache = (key: null, p0: 0);

/// Largest head position at which the whole ribbon is still off screen.
double _entryStart(Size size, double extent, Offset shift) {
  final scale = extent / Ribbon.bounds.width;
  final origin = size.center(shift) - Ribbon.bounds.center * scale;
  bool visible(double head) {
    final e = Ribbon.edges(head);
    final r = (Offset.zero & size).inflate(12);
    for (var k = 0; k < e.a.length; k += 4) {
      if (r.contains(origin + e.a[k] * scale) || r.contains(origin + e.b[k] * scale)) return true;
    }
    return false;
  }

  var lo = -4 * Ribbon.closed, hi = 0.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (visible(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return lo;
}
