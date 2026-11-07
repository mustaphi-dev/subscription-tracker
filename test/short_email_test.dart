import 'package:flutter_test/flutter_test.dart';
import 'package:wince/signin.dart';

void main() {
  test('shortEmail trims long names and keeps short ones', () {
    expect(shortEmail('adamsmustapha889@gmail.com'), 'adamsm…@gmail.com');
    expect(shortEmail('ama@gmail.com'), 'ama@gmail.com');
  });
}
