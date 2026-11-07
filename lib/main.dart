import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'country.dart';
import 'data.dart';
import 'forwarding.dart';
import 'item_tile.dart';
import 'lock.dart';
import 'onboarding.dart';
import 'profile.dart';
import 'push.dart';
import 'shell.dart';
import 'signin.dart';
import 'tab_page.dart';
import 'ui.dart';
import 'upcoming.dart';
import 'widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Publishable values (public by design; RLS protects data). Override with --dart-define-from-file=env.json.
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nvdbtfnfnimamiolbqwk.supabase.co'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_MQvdhrt01UD9No8F5mo9HA_puUTELEP'),
  );
  await HomeWidget.setAppGroupId('group.app.trywince.wince');
  await loadOnboarded();
  runApp(const ProviderScope(child: App()));
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = db.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final router = GoRouter(
  refreshListenable: Listenable.merge([_AuthRefresh(), onboarded, needsCountry]),
  redirect: (_, s) {
    final signedIn = db.auth.currentSession != null;
    final at = s.matchedLocation;
    if (!signedIn) {
      // First launch: welcome pages, then sign-in. Signed-in users never see onboarding.
      if (!onboarded.value) return at == '/welcome' ? null : '/welcome';
      return at.startsWith('/signin') ? null : '/signin';
    }
    // The email screen plays its "You're in" beat when the magic link lands, then moves on.
    if (at == '/signin/email') return null;
    // New accounts pick where they bank before anything else.
    if (needsCountry.value) return at == '/country' ? null : '/country';
    if (at.startsWith('/signin') || at == '/welcome' || at == '/country') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const ShellScreen()),
    // Onboarding and sign-in share one stage, so they cross-fade instead of sliding.
    GoRoute(path: '/welcome', pageBuilder: (_, s) => _stagePage(s, const OnboardingScreen())),
    GoRoute(
      path: '/signin',
      pageBuilder: (_, s) => _stagePage(s, const SignInScreen()),
      routes: [GoRoute(path: 'email', pageBuilder: (_, s) => _stagePage(s, EmailScreen(email: s.extra as String?)))],
    ),
    GoRoute(path: '/country', builder: (_, _) => const CountryScreen()),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/forwarding', builder: (_, _) => const ForwardingScreen()),
    GoRoute(path: '/upcoming', builder: (_, _) => const UpcomingScreen()),
    GoRoute(path: confirmPath(':id'), builder: (_, s) => ConfirmTrialScreen(s.pathParameters['id']!)),
  ],
);

Page<void> _stagePage(GoRouterState s, Widget child) => CustomTransitionPage<void>(
  key: s.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 450),
  reverseTransitionDuration: const Duration(milliseconds: 350),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
);

class App extends ConsumerStatefulWidget {
  const App({super.key});
  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  StreamSubscription? _links;

  @override
  void initState() {
    super.initState();
    // Anyone already signed in has effectively onboarded; don't show it after a later sign-out.
    if (db.auth.currentSession != null && !onboarded.value) finishOnboarding();
    initPush(router);
    // Bank OAuth returns to wince://bank-connected.
    _links = AppLinks().uriLinkStream.listen((uri) {
      if (uri.host != 'bank-connected') return;
      ref.invalidate(sourcesProvider);
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      if (uri.queryParameters['status'] == 'failed') {
        showError(ctx, 'Your bank didn\'t share access, so nothing was connected.');
      } else {
        showToast(ctx, 'Bank connected');
      }
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  void _home() {
    router.routerDelegate.navigatorKey.currentState?.popUntil((r) => r.isFirst);
    router.go('/');
    goToTab(ref, AppTab.home);
  }

  @override
  Widget build(BuildContext context) {
    // The router already moves between sign-in and the app; this just drops the old tab.
    ref.listen(uidProvider, (_, _) => goToTab(ref, AppTab.home));
    // Coming back through the lock (or a new sign-in) starts on Home, not wherever you left off.
    ref.listen(lockProvider, (_, locked) => locked ? _home() : null);
    ref.listen(profileProvider, (_, next) {
      final p = next.value;
      needsCountry.value = p != null && p.country == null;
    });
    // The home-screen widget shows the next trials in the display currency, so either change redraws it.
    void syncWidget() {
      final items = ref.read(itemsProvider).value;
      if (items != null) updateTrialWidget(items, ref.read(baseProvider));
    }
    ref.listen(itemsProvider, (_, _) => syncWidget());
    ref.listen(baseProvider, (_, _) => syncWidget());

    return MaterialApp.router(
      title: 'Wince',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      builder: (context, child) => Stack(children: [
        LockGate(child: child!),
        const Positioned.fill(child: SplashOverlay()),
      ]),
    );
  }
}
