import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'ui.dart';
import 'home.dart';
import 'lock.dart';
import 'country.dart';
import 'onboarding.dart';
import 'profile.dart';
import 'push.dart';
import 'forwarding.dart';
import 'screens.dart';
import 'signin.dart';

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
    _sub = db.auth.onAuthStateChange.listen((_) {
      refreshNeedsCountry();
      notifyListeners();
    });
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
      routes: [GoRoute(path: 'email', pageBuilder: (_, s) => _stagePage(s, const EmailScreen()))],
    ),
    GoRoute(path: '/country', builder: (_, _) => const CountryScreen()),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/forwarding', builder: (_, _) => const ForwardingScreen()),
    GoRoute(path: '/upcoming', builder: (_, _) => const UpcomingScreen()),
    GoRoute(path: '/confirm/:id', builder: (_, s) => ConfirmTrialScreen(s.pathParameters['id']!)),
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

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool? _hasPin;
  StreamSubscription? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PinStore.hasPin().then((v) => setState(() => _hasPin = v));
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
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(obscureProvider.notifier).set(state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ref.read(lockProvider.notifier).backgrounded();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(lockProvider.notifier).resumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the home-screen widget in sync with live data.
    ref.listen(itemsProvider, (_, next) {
      final items = next.value;
      if (items != null) updateTrialWidget(items, ref.read(baseCurrencyProvider).value ?? 'GBP');
    });

    final locked = ref.watch(lockProvider);
    final obscured = ref.watch(obscureProvider);
    final signedIn = ref.watch(authProvider).value?.session ?? db.auth.currentSession;

    return MaterialApp.router(
      title: 'Wince',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      builder: (context, child) => Stack(children: [
        child!,
        // Lock gate sits above every route so no content renders underneath on resume.
        if (signedIn != null && _hasPin != null && (locked || !_hasPin!))
          Positioned.fill(
            child: LiquidGlassLockScreen(
              key: ValueKey(_hasPin),
              setup: !_hasPin!,
              onDone: () => setState(() => _hasPin = true),
            ),
          ),
        if (obscured) const Positioned.fill(child: PrivacyShield()),
        const Positioned.fill(child: SplashOverlay()),
      ]),
    );
  }
}
