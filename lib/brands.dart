import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Merchant and bank logos from logo.dev, cached on disk after the first load.
///
/// Pass the publishable key at build time: `--dart-define=LOGO_DEV_KEY=pk_...`
/// (safe in the client; never ship the `sk_` secret key). Without a key, or when a logo
/// doesn't exist or can't load, callers get their own letter-tile fallback.
const _key = String.fromEnvironment('LOGO_DEV_KEY');

/// Exact domains for brands whose names arrive messy from bank feeds and receipts
/// ("AMZN Mktp", "APPLE.COM/BILL", "UBER *EATS") or are ambiguous on their own ("Sky", "Three").
/// Order matters: specific before generic. Aliases are lowercase with spaces and punctuation removed.
const _domains = <(List<String>, String)>[
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
  (['revolut'], 'revolut.com'),
  (['wise', 'transferwise'], 'wise.com'),
  (['monzo'], 'monzo.com'),
  (['starling'], 'starlingbank.com'),
  (['lloyds'], 'lloydsbank.com'),
  (['barclays', 'barclaycard'], 'barclays.co.uk'),
  (['hsbc'], 'hsbc.co.uk'),
  (['natwest'], 'natwest.com'),
  (['santander'], 'santander.co.uk'),
  (['halifax'], 'halifax.co.uk'),
  (['nationwide'], 'nationwide.co.uk'),
  (['chase'], 'chase.co.uk'),
  (['amex', 'americanexpress'], 'americanexpress.com'),
  (['paypal'], 'paypal.com'),
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

final _urlCache = <String, String?>{};

/// Logo URL at [px] physical pixels, or null when no key is configured or the name is unusable.
String? logoUrl(String name, int px) {
  if (_key.isEmpty) return null;
  return _urlCache.putIfAbsent('$name@$px', () {
    final q = logoQuery(name);
    if (q == null) return null;
    final path = q.domain ?? 'name/${Uri.encodeComponent(q.name!)}';
    // fallback=404: unknown brands fail instead of returning a generic monogram, so our own letter tile shows.
    return 'https://img.logo.dev/$path?token=$_key&size=$px&format=png&fallback=404';
  });
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
