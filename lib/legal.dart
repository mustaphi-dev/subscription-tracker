import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui.dart';

const kPrivacyUrl = 'https://mustaphi-dev.github.io/subscription-tracker/privacy.html';
const kTermsUrl = 'https://mustaphi-dev.github.io/subscription-tracker/terms.html';
const kSupportEmail = 'hello@trywince.app';

void openLegal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// Privacy Policy · Terms of Service, opening the GitHub Pages copies.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  Widget _link(String text, String url) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => openLegal(url),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(text, style: TextStyle(color: kText.withValues(alpha: 0.72), fontSize: 14, fontWeight: FontWeight.w500)),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _link('Privacy Policy', kPrivacyUrl),
      Container(width: 3, height: 3, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: const BoxDecoration(color: kFaint, shape: BoxShape.circle)),
      _link('Terms of Service', kTermsUrl),
    ],
  );
}
