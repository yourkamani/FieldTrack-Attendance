import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'database_helper.dart';

const Duration kMaxSessionDuration = Duration(hours: 12);

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_tracking',
    'Location Tracking',
    description: 'This channel is used for background location tracking.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'location_tracking',
      initialNotificationTitle: 'Tracking Active',
      initialNotificationContent: 'Recording location offline',
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // This isolate is separate from main.dart's — Supabase must be
  // initialized here too, or any Supabase.instance.client call throws.
  await Supabase.initialize(
    url: 'https://tmoacgbszammuasaxapo.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtb2FjZ2JzemFtbXVhc2F4YXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3OTg1MzgsImV4cCI6MjEwMjM3NDUzOH0.NJxYtAyRXPMi8P7H-sClCOpWcBIhqGwz-6TvastkeUw',
  );

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';

  // ...rest of onStart unchanged

  final sessionId = prefs.getString('current_session_id') ?? DateTime.now().millisecondsSinceEpoch.toString();
  final sessionStartRaw = prefs.getString('current_session_start');
  final sessionStart = sessionStartRaw != null ? DateTime.parse(sessionStartRaw) : DateTime.now();

  // Isolate-local flag so we only ping the admin ONCE per GPS-off spell,
  // not every minute for as long as it stays off.
  bool gpsOffAlertSent = false;

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (DateTime.now().difference(sessionStart) >= kMaxSessionDuration) {
      // ... unchanged auto-stop block ...
      timer.cancel();
      await DatabaseHelper.instance.updateSessionAutoStop(
        sessionId: sessionId,
        endTime: DateTime.now().toIso8601String(),
      );
      await prefs.remove('current_session_id');
      await prefs.remove('current_session_start');
      service.stopSelf();
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    bool hasInternet = await InternetConnectionChecker.createInstance().hasConnection;

    if (!serviceEnabled) {
      if (service is AndroidServiceInstance && await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'Tracking Paused',
          content: 'Please turn on GPS to resume tracking.',
        );
      }

      if (hasInternet) {
        try {
          await Supabase.instance.client.from('live_locations').upsert({
            'user_id': userId,
            'gps_enabled': false,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id');

          if (!gpsOffAlertSent) {
            gpsOffAlertSent = true;

            final userRow = await Supabase.instance.client
                .from('users')
                .select('name, phone')
                .eq('id', userId)
                .maybeSingle();
            final userName = userRow?['name'] ?? 'Unknown user';
            final userPhone = userRow?['phone'] ?? '';

            // Source of truth — the notifications screen reads this table.
            await Supabase.instance.client.from('notifications').insert({
              'user_id': userId,
              'user_name': userName,
              'user_phone': userPhone,
              'type': 'location_off',
              'message': '$userName turned off their location.',
            });

            // Push is just for the immediate OS banner/sound.
            await Supabase.instance.client.functions.invoke('send-push', body: {
              'kind': 'location_off_alert',
              'user_id': userId,
              'user_name': userName,
              'user_phone': userPhone,
            });
          }
        } catch (e) {
          print('Failed to report GPS-off state: $e');
        }
      }
      return;
    }
    
    // GPS is back on — reset the flag so a future off-spell alerts again.
    gpsOffAlertSent = false;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await DatabaseHelper.instance.insertLocation({
        'user_id': userId,
        'session_id': sessionId,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Best-effort live write — separate from the offline sync queue
      // above, which is for the full track history.
      if (hasInternet) {
        try {
          await Supabase.instance.client.from('live_locations').upsert({
            'user_id': userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'gps_enabled': true,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id');
        } catch (e) {
          print('Failed to write live location: $e');
        }
      }

      if (service is AndroidServiceInstance && await service.isForegroundService()) {
        final now = DateTime.now();
        final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        service.setForegroundNotificationInfo(
          title: 'Tracking Active',
          content: 'Last location saved at $timeString',
        );
      }
    } catch (e) {
      print("Error fetching location: $e");
    }
  });
}