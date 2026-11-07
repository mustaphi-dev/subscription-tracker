import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wince/brand_mark.dart';

void main() {
  test('the W splash layers are all in the bundle', () {
    for (final a in kMarkLayers) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });

  testWidgets('BrandMark builds finished and mid-animation', (tester) async {
    for (final m in const [
      BrandMark(size: 200),
      BrandMark(size: 200, middle: 0.5, legs: 0.2, flinch: 0, sheen: -1),
      BrandMark(size: 200, middle: 1, legs: 1, flinch: 1, sheen: 0.5),
    ]) {
      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Center(child: m)));
      expect(tester.getSize(find.byType(BrandMark)), const Size(200, 200));
      expect(find.byType(Image), findsWidgets);
    }
  });
}
