import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'data.dart';

/// Merchant and bank logos from logo.dev, cached on disk after the first load.
///
/// Pass the publishable key at build time: `--dart-define=LOGO_DEV_KEY=pk_...`
/// (safe in the client; never ship the `sk_` secret key). Without a key, or when a logo
/// doesn't exist or can't load, callers get their own letter-tile fallback.
const _key = String.fromEnvironment('LOGO_DEV_KEY');

/// Banks the app knows by name: the key the server stores as `provider`, brand colour, logo
/// domain and the page their app claims. The first four are offered one-tap on Accounts.
typedef Bank = ({String key, String label, Color color, List<String> aliases, String domain, String app});

const banks = <Bank>[
  (key: 'revolut', label: 'Revolut', color: Color(0xFF3D7BFF), aliases: [], domain: 'revolut.com', app: 'https://revolut.com/app'),
  (key: 'wise', label: 'Wise', color: Color(0xFF9FE870), aliases: ['transferwise'], domain: 'wise.com', app: 'https://wise.com/account'),
  (key: 'lloyds', label: 'Lloyds', color: Color(0xFF00A56A), aliases: [], domain: 'lloydsbank.com', app: 'https://www.lloydsbank.com/app.html'),
  (key: 'paypal', label: 'PayPal', color: Color(0xFF6C63FF), aliases: [], domain: 'paypal.com', app: 'https://www.paypal.com/myaccount/autopay'),
];

/// The known bank whose key appears in [name] ("Lloyds Bank" → Lloyds).
Bank? bankNamed(String name) {
  final n = name.toLowerCase();
  return banks.where((b) => n.contains(b.key)).firstOrNull;
}

/// A stable colour for anything without a brand colour, from its name.
Color nameColor(String name, [double saturation = 0.55, double lightness = 0.6]) =>
    HSLColor.fromAHSL(1, (name.toLowerCase().hashCode % 360).abs().toDouble(), saturation, lightness).toColor();

/// A bank's brand colour if the app knows it, otherwise a stable colour from its name.
Color bankColor(String bank) => bankNamed(bank)?.color ?? nameColor(bank);

extension SourceLook on PaymentSource {
  /// Bank name to show: the provider's, or whatever the user typed for other banks.
  String get bank => banks.where((b) => b.key == provider).firstOrNull?.label ?? institution ?? 'Bank';
  Color get color => bankColor(bank);
}

/// The bank's site for [s]; iOS hands it to the bank's app when that app claims the link.
String? bankAppUrl(PaymentSource? s) {
  if (s == null) return null;
  final domain = logoQuery('${s.provider} ${s.institution ?? ''}')?.domain;
  if (domain == null) return null;
  return banks.where((b) => b.domain == domain).firstOrNull?.app ?? 'https://www.$domain';
}

/// Exact domains for brands whose names arrive messy from bank feeds and receipts
/// ("AMZN Mktp", "APPLE.COM/BILL", "UBER *EATS") or are ambiguous on their own ("Sky", "Three").
/// Order matters: specific before generic. Aliases are lowercase with spaces and punctuation removed.
final _domains = <(List<String>, String)>[
  // Streaming & media
  (['youtubemusic', 'youtubepremium', 'youtube'], 'youtube.com'),
  (['netflix'], 'netflix.com'),
  (['spotify'], 'spotify.com'),
  (['disneyplus', 'disney'], 'disneyplus.com'),
  (['primevideo', 'amazonprime', 'prime'], 'primevideo.com'),
  (['audible'], 'audible.co.uk'),
  (['kindle'], 'amazon.co.uk'),
  (['amzn', 'amazon'], 'amazon.co.uk'),
  (['icloud'], 'icloud.com'),
  (['apple', 'itunes', 'appstore'], 'apple.com'),
  (['nowtv'], 'nowtv.com'),
  (['sky'], 'sky.com'),
  (['hbomax', 'hbo'], 'max.com'),
  (['paramount'], 'paramountplus.com'),
  (['dazn'], 'dazn.com'),
  (['crunchyroll'], 'crunchyroll.com'),
  (['playstation', 'psn', 'sonyinteractive'], 'playstation.com'),
  (['xbox', 'gamepass'], 'xbox.com'),
  (['steam', 'steampowered', 'valve'], 'steampowered.com'),
  (['nintendo'], 'nintendo.com'),
  (['twitch'], 'twitch.tv'),
  (['patreon'], 'patreon.com'),
  // Software & AI
  (['chatgpt', 'openai'], 'openai.com'),
  (['claude', 'anthropic'], 'claude.ai'),
  (['googleone', 'googlestorage', 'googleplay', 'google', 'gsuite'], 'google.com'),
  (['microsoft', 'msft', 'office365', 'microsoft365', 'onedrive'], 'microsoft.com'),
  (['adobe', 'creativecloud'], 'adobe.com'),
  (['canva'], 'canva.com'),
  (['notion'], 'notion.so'),
  (['dropbox'], 'dropbox.com'),
  (['linkedin'], 'linkedin.com'),
  // Lifestyle
  (['duolingo'], 'duolingo.com'),
  (['headspace'], 'headspace.com'),
  (['calm'], 'calm.com'),
  (['strava'], 'strava.com'),
  (['tinder'], 'tinder.com'),
  (['bumble'], 'bumble.com'),
  (['hinge'], 'hinge.co'),
  (['ubereats'], 'ubereats.com'),
  (['uber'], 'uber.com'),
  (['deliveroo'], 'deliveroo.co.uk'),
  (['justeat'], 'just-eat.co.uk'),
  (['hellofresh'], 'hellofresh.co.uk'),
  (['puregym'], 'puregym.com'),
  // Pay later
  (['klarna'], 'klarna.com'),
  (['clearpay'], 'clearpay.co.uk'),
  (['afterpay'], 'afterpay.com'),
  // Banks & payments
  for (final b in banks) ([b.key, ...b.aliases], b.domain),
  (['monzo'], 'monzo.com'),
  (['starling'], 'starlingbank.com'),
  (['barclays', 'barclaycard'], 'barclays.co.uk'),
  (['hsbc'], 'hsbc.co.uk'),
  (['natwest'], 'natwest.com'),
  (['santander'], 'santander.co.uk'),
  (['halifax'], 'halifax.co.uk'),
  (['nationwide'], 'nationwide.co.uk'),
  (['chase'], 'chase.co.uk'),
  (['amex', 'americanexpress'], 'americanexpress.com'),
  (['n26'], 'n26.com'),
  (['gcb'], 'gcbbank.com.gh'),
  (['ecobank'], 'ecobank.com'),
  (['momo', 'mtn'], 'mtn.com'),
  // Mobile
  (['vodafone'], 'vodafone.co.uk'),
  (['o2'], 'o2.co.uk'),
  (['ee'], 'ee.co.uk'),
  (['three'], 'three.co.uk'),
  (['airtel'], 'airtel.com'),
];

/// Bank-feed noise to drop before a name lookup ("Netflix.com UK Ltd Subscription" → "netflix").
const _noise = {
  'com', 'co', 'uk', 'gb', 'www', 'http', 'https', 'ltd', 'limited', 'inc', 'llc', 'plc', 'bill', 'billing',
  'subscription', 'subscriptions', 'payment', 'payments', 'membership', 'monthly', 'annual', 'help', 'online',
  'digital', 'services', 'service', 'the', 'paypal', 'sq', 'sumup', 'zettle', 'stripe', 'card', 'purchase',
};

List<String> _words(String name) => name.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();

/// What logo.dev should be asked for: a known domain, a cleaned brand name, or null for nothing usable.
({String? domain, String? name})? logoQuery(String raw) {
  final words = _words(raw);
  if (words.isEmpty) return null;
  final joined = words.join();
  for (final (aliases, domain) in _domains) {
    for (final a in aliases) {
      // Short aliases ("sky", "ee", "uber") must be a whole word so "purchase" never matches "chase".
      if (words.contains(a) || (a.length >= 5 && joined.startsWith(a)) || (a.length >= 6 && joined.contains(a))) {
        return (domain: domain, name: null);
      }
    }
  }
  // Unknown merchant: strip noise and reference numbers, keep the first two words as the brand.
  final brand = words.where((w) => !_noise.contains(w) && !RegExp(r'^\d+$').hasMatch(w)).take(2).join(' ');
  return brand.length < 2 ? null : (domain: null, name: brand);
}

/// Logo URL at [px] physical pixels, or null when no key is configured or the name is unusable.
String? logoUrl(String name, int px) {
  if (_key.isEmpty) return null;
  final q = logoQuery(name);
  if (q == null) return null;
  final path = q.domain ?? 'name/${Uri.encodeComponent(q.name!)}';
  // fallback=404: unknown brands fail instead of returning a generic monogram, so our own letter tile shows.
  return 'https://img.logo.dev/$path?token=$_key&size=$px&format=png&fallback=404';
}

/// Rounded logo for [name]; shows [fallback] while loading, offline, or when there's no logo.
class LogoTile extends StatelessWidget {
  const LogoTile(this.name, {super.key, required this.size, required this.fallback, this.radius});
  final String name;
  final double size;
  final Widget fallback;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    final url = logoUrl(name, px);
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.3),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: px,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
