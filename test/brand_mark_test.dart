import 'package:flutter_test/flutter_test.dart';
import 'package:subtracker/brand_mark_path.dart';

void main() {
  test('groove path sits inside the mark image and runs top to bottom', () {
    expect(kMarkGroove.length, greaterThan(100));
    for (final p in kMarkGroove) {
      expect(p.dx, inInclusiveRange(0, 1));
      expect(p.dy, inInclusiveRange(0, 1));
    }
    expect(kMarkGroove.first.dy, lessThan(0.4)); // starts at the top terminal
    expect(kMarkGroove.last.dy, greaterThan(0.6)); // ends at the bottom terminal
    expect(kMarkGrooveWidth, inExclusiveRange(0, 0.05));
  });

  test('groove path is continuous (no jumps across the twist)', () {
    for (var i = 1; i < kMarkGroove.length; i++) {
      expect((kMarkGroove[i] - kMarkGroove[i - 1]).distance, lessThan(0.03));
    }
  });
}
