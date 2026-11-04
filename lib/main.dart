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
import 'push.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Publishable values (public by design; RLS protects data). Override with --dart-define-from-file=env.json.
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nvdbtfnfnimamiolbqwk.supabase.co'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_MQvdhrt01UD9No8F5mo9HA_puUTELEP'),
  );
  await HomeWidget.setAppGroupId('group.com.lovefist.subtracker');
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
  refreshListenable: _AuthRefresh(),
  redirect: (_, s) {
    final signedIn = db.auth.currentSession != null;
    if (!signedIn) return s.matchedLocation == '/signin' ? null : '/signin';
    if (s.matchedLocation == '/signin') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const ShellScreen()),
    GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
    GoRoute(path: '/confirm/:id', builder: (_, s) => ConfirmTrialScreen(s.pathParameters['id']!)),
  ],
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
    initPush(router);
    // Bank OAuth returns to subtracker://bank-connected.
    _links = AppLinks().uriLinkStream.listen((uri) {
      if (uri.host == 'bank-connected') ref.invalidate(sourcesProvider);
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
      title: 'Subtracker',
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
      ]),
    );
  }
}
