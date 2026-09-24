import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Supabase.initialize(
    url: 'https://ctfhrpohgqqvbdxglebw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0ZmhycG9oZ3FxdmJkeGdsZWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNjA5MDMsImV4cCI6MjEwNTczNjkwM30.k-kGhWvH3k1Iet6cR6zrn7kUbuGnGaYP64KLMMAkLb8',
  );
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static final _supabase = Supabase.instance.client;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> init({
    required String ownerType,
    required String ownerId,
    required String businessId,
  }) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(ownerType, ownerId, businessId, token);

    _messaging.onTokenRefresh.listen((newToken) => _saveToken(ownerType, ownerId, businessId, newToken));

    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'location_off_alert') {
        final name = message.data['user_name'] ?? 'A user';
        await showLocalNotification('Location Off', '$name turned off their location.');
      }
    });
  }

  static Future<void> _saveToken(String ownerType, String ownerId, String businessId, String token) async {
    await _supabase.from('device_tokens').upsert({
      'owner_type': ownerType,
      'owner_id': ownerId,
      'business_id': businessId,
      'fcm_token': token,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'owner_type,owner_id');
  }

  static Future<void> showLocalNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails('alerts', 'Alerts', importance: Importance.high, priority: Priority.high);
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}