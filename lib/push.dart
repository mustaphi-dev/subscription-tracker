import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'data.dart';
import 'ui.dart';

final _local = FlutterLocalNotificationsPlugin();
const _channel = AndroidNotificationChannel('alerts', 'Trial & shortfall alerts', importance: Importance.high);

/// FCM + local notifications. No-op if Firebase isn't configured yet (`flutterfire configure`).
Future<void> initPush(GoRouter router) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission();

  await _local.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (r) => _route(router, jsonDecode(r.payload ?? '{}')),
  );
  await _local
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  Future<void> saveToken(String? t) async {
    final uid = db.auth.currentUser?.id;
    if (t != null && uid != null) await db.from('profiles').update({'fcm_token': t}).eq('id', uid);
  }

  await saveToken(await fcm.getToken());
  fcm.onTokenRefresh.listen(saveToken);
  db.auth.onAuthStateChange.listen((s) async {
    if (s.event == AuthChangeEvent.signedIn) await saveToken(await fcm.getToken());
  });

  // Foreground: FCM doesn't display, so mirror it locally.
  FirebaseMessaging.onMessage.listen((m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name, importance: Importance.high),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(m.data),
    );
  });
  FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(router, m.data));
  final initial = await fcm.getInitialMessage();
  if (initial != null) _route(router, initial.data);
}

void _route(GoRouter router, Map<String, dynamic> data) {
  final id = data['item_id'];
  if (id != null) router.go('/confirm/$id');
}

/// Push the next expiring trials into the native home-screen widget.
Future<void> updateTrialWidget(List<FinancialItem> items, String base) async {
  final trials = items
      .where((i) => i.isTrial && i.status == 'active' && i.trialEnd != null && i.trialEnd!.isAfter(DateTime.now()))
      .take(3)
      .map((t) => {
            'name': t.merchant,
            'ends_at': t.trialEnd!.millisecondsSinceEpoch,
            'charge': t.baseAmount == null ? '?' : money(t.baseAmount!, base),
          })
      .toList();
  try {
    await HomeWidget.saveWidgetData('trials', jsonEncode(trials));
    await HomeWidget.updateWidget(androidName: 'TrialWidgetProvider', iOSName: 'TrialWidget');
  } catch (_) {
    // Widget extension not installed (e.g. iOS target not yet added in Xcode).
  }
}
