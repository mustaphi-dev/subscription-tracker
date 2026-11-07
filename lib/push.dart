import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'data.dart';
import 'item_tile.dart' show confirmPath;

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
    if (t != null && db.auth.currentUser != null) await updateProfile({'fcm_token': t});
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
  if (id != null) router.go(confirmPath('$id'));
}
