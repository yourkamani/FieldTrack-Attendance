import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must be a top-level function (not a class method) and carry this
/// annotation, or Android won't be able to invoke it when the app
/// is fully killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // A new isolate — Supabase needs re-init here.
  await Supabase.initialize(
    url: 'https://tmoacgbszammuasaxapo.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtb2FjZ2JzemFtbXVhc2F4YXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3OTg1MzgsImV4cCI6MjEwMjM3NDUzOH0.NJxYtAyRXPMi8P7H-sClCOpWcBIhqGwz-6TvastkeUw',
  );

  if (message.data['type'] == 'location_off_alert') {
    await FcmService.showLocalNotification(
      'Location Off',
      'A user turned off their location.',
    );
  }
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static final _supabase = Supabase.instance.client;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Call once after any successful login (user or admin).
  static Future<void> init({
    required String ownerType, // 'user' | 'admin'
    required String ownerId,
  }) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(ownerType, ownerId, token);
    }

    // Token can rotate; keep it fresh.
    _messaging.onTokenRefresh.listen((newToken) {
      _saveToken(ownerType, ownerId, newToken);
    });

    // Foreground messages: admin's app is open when the alert arrives.
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'location_off_alert') {
        showLocalNotification('Location Off', 'A user turned off their location.');
      }
    });
  }

  static Future<void> _saveToken(String ownerType, String ownerId, String token) async {
    await _supabase.from('device_tokens').upsert({
      'owner_type': ownerType,
      'owner_id': ownerId,
      'fcm_token': token,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'owner_type,owner_id');
  }

  static Future<void> showLocalNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'alerts',
      'Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}