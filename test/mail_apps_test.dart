import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wince/mail_apps.dart';

void main() {
  test('the inbox button names the app the address points to', () {
    expect(MailApp.forEmail('mustapha@gmail.com').action, 'Open Gmail');
    expect(MailApp.forEmail(' Someone@GoogleMail.com ').action, 'Open Gmail');
    expect(MailApp.forEmail('a@outlook.com'), MailApp.outlook);
    expect(MailApp.forEmail('a@hotmail.co.uk'), MailApp.outlook);
    expect(MailApp.forEmail('a@yahoo.com'), MailApp.yahoo);
    expect(MailApp.forEmail('a@icloud.com', TargetPlatform.iOS), MailApp.appleMail);
    expect(MailApp.forEmail('a@icloud.com', TargetPlatform.android), MailApp.any);
    expect(MailApp.forEmail('a@trywince.app').action, 'Open mail app');
  });
}
