import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/ribbon.dart';

void main() {
  const screen = Size(390, 844);

  test('closed ribbon frames to the logo proportions', () {
    final b = Ribbon.bounds;
    expect(b.width, closeTo(2.46, 0.05));
    expect(b.height, closeTo(1.35, 0.05));
  });

  test('entrance starts off screen and ends exactly closed', () {
    expect(ribbonEntrance(1, screen, 240), Ribbon.closed);
    final start = ribbonEntrance(0, screen, 240);
    expect(start, lessThan(0));
    // Off screen at the start: every edge point lies outside the canvas.
    final scale = 240 / Ribbon.bounds.width;
    final origin = screen.center(Offset.zero) - Ribbon.bounds.center * scale;
    final e = Ribbon.edges(start);
    for (final p in [...e.a, ...e.b]) {
      expect((Offset.zero & screen).contains(origin + p * scale), isFalse);
    }
  });

  test('entrance only ever moves forward', () {
    var last = double.negativeInfinity;
    for (var i = 0; i <= 100; i++) {
      final p = ribbonEntrance(i / 100, screen, 240);
      expect(p, greaterThanOrEqualTo(last));
      last = p;
    }
  });

  test('ends meet when closed', () {
    final e = Ribbon.edges(Ribbon.closed);
    // The head runs 0.4% past the tail; the gap between the two ends is tiny and the
    // edges cross over (half twist): tail's left edge meets head's right edge.
    expect((e.a.first - e.b.last).distance, lessThan(0.05));
    expect((e.b.first - e.a.last).distance, lessThan(0.05));
  });
}
