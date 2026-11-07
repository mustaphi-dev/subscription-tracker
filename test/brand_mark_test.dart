import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wince/brand_mark.dart';

void main() {
  test('the W splash layers are all in the bundle', () {
    for (final a in kMarkLayers) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });
}
