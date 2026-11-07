import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The mail app most likely to hold the sign-in link, picked from the address, so the
/// "Check your inbox" button can say "Open Gmail" and land the user in their inbox.
/// The Android packages are declared under `<queries>` in AndroidManifest.xml.
enum MailApp {
  gmail('Gmail', 'googlegmail://', 'com.google.android.gm'),
  outlook('Outlook', 'ms-outlook://', 'com.microsoft.office.outlook'),
  yahoo('Yahoo Mail', 'ymail://', 'com.yahoo.mobile.client.android.mail'),
  appleMail('Mail', 'message://', null),
  any('mail app', null, null);

  const MailApp(this.label, this.iosUrl, this.androidPackage);
  final String label;
  final String? iosUrl, androidPackage;

  /// "Open Gmail", "Open Outlook", … or "Open mail app" when the domain says nothing.
  String get action => 'Open $label';

  static MailApp forEmail(String email, [TargetPlatform? platform]) {
    final domain = email.split('@').last.trim().toLowerCase();
    if (domain == 'gmail.com' || domain == 'googlemail.com') return gmail;
    if (RegExp(r'^(outlook|hotmail|live|msn)\.').hasMatch(domain)) return outlook;
    if (RegExp(r'^(yahoo|ymail|rocketmail)\.').hasMatch(domain)) return yahoo;
    if (const {'icloud.com', 'me.com', 'mac.com'}.contains(domain)) {
      return (platform ?? defaultTargetPlatform) == TargetPlatform.iOS ? appleMail : any;
    }
    return any;
  }
}

/// Opens [app] at its inbox, falling back to the phone's mail app. False if nothing opened.
Future<bool> openMailApp(MailApp app) async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      final urls = {
        ?app.iosUrl,
        if (app == MailApp.any) ...['googlegmail://', 'ms-outlook://'],
        'message://',
      };
      for (final url in urls) {
        try {
          if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return true;
        } catch (e) {
          debugPrint('open $url: $e');
        }
      }
      return false;
    case TargetPlatform.android:
      final intents = [
        if (app.androidPackage case final pkg?)
          AndroidIntent(action: 'android.intent.action.MAIN', category: 'android.intent.category.LAUNCHER', package: pkg, flags: const [Flag.FLAG_ACTIVITY_NEW_TASK]),
        const AndroidIntent(action: 'android.intent.action.MAIN', category: 'android.intent.category.APP_EMAIL', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]),
      ];
      for (final intent in intents) {
        try {
          // launch() quietly drops the package when it can't resolve, so check first.
          if (await intent.canResolveActivity() ?? false) {
            await intent.launch();
            return true;
          }
        } catch (e) {
          debugPrint('open mail app: $e');
        }
      }
      return false;
    default:
      return false;
  }
}
