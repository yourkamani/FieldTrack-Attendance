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
  const channel = AndroidNotificationChannel('location_tracking', 'Location Tracking',
      description: 'This channel is used for background location tracking.', importance: Importance.low);
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: false, isForegroundMode: true,
      notificationChannelId: 'location_tracking',
      initialNotificationTitle: 'Tracking Active', initialNotificationContent: 'Recording location offline',
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart, onBackground: onIosBackground),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async => true;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await Supabase.initialize(url: 'https://ctfhrpohgqqvbdxglebw.supabase.co', anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0ZmhycG9oZ3FxdmJkeGdsZWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNjA5MDMsImV4cCI6MjEwNTczNjkwM30.k-kGhWvH3k1Iet6cR6zrn7kUbuGnGaYP64KLMMAkLb8');

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';
  final businessId = prefs.getString('business_id') ?? '';

  final sessionId = prefs.getString('current_session_id') ?? DateTime.now().millisecondsSinceEpoch.toString();
  final sessionStartRaw = prefs.getString('current_session_start');
  final sessionStart = sessionStartRaw != null ? DateTime.parse(sessionStartRaw) : DateTime.now();

  bool gpsOffAlertSent = false;

  service.on('stopService').listen((event) => service.stopSelf());

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (DateTime.now().difference(sessionStart) >= kMaxSessionDuration) {
      timer.cancel();
      await DatabaseHelper.instance.updateSessionAutoStop(sessionId: sessionId, endTime: DateTime.now().toIso8601String());
      await prefs.remove('current_session_id');
      await prefs.remove('current_session_start');
      service.stopSelf();
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    bool hasInternet = await InternetConnectionChecker.createInstance().hasConnection;

    if (!serviceEnabled) {
      if (service is AndroidServiceInstance && await service.isForegroundService()) {
        service.setForegroundNotificationInfo(title: 'Tracking Paused', content: 'Please turn on GPS to resume tracking.');
      }
      if (hasInternet) {
        try {
          await Supabase.instance.client.rpc('upsert_live_location', params: {
            'p_user_id': userId, 'p_business_id': businessId,
            'p_latitude': null, 'p_longitude': null, 'p_gps_enabled': false,
          });

          if (!gpsOffAlertSent) {
            gpsOffAlertSent = true;
            final userRow = await Supabase.instance.client.from('users').select('name, phone').eq('id', userId).maybeSingle();
            final userName = userRow?['name'] ?? 'Unknown user';
            final userPhone = userRow?['phone'] ?? '';

            await Supabase.instance.client.from('notifications').insert({
              'user_id': userId, 'business_id': businessId, 'user_name': userName, 'user_phone': userPhone,
              'type': 'location_off', 'message': '$userName turned off their location.',
            });

            await Supabase.instance.client.functions.invoke('send-push', body: {
              'kind': 'location_off_alert', 'user_id': userId, 'business_id': businessId,
              'user_name': userName, 'user_phone': userPhone,
            });
          }
        } catch (e) {
          print('Failed to report GPS-off state: $e');
        }
      }
      return;
    }

    gpsOffAlertSent = false;

    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      await DatabaseHelper.instance.insertLocation({
        'user_id': userId, 'business_id': businessId, 'session_id': sessionId,
        'lat': position.latitude, 'lng': position.longitude, 'timestamp': DateTime.now().toIso8601String(),
      });

      if (hasInternet) {
        try {
          await Supabase.instance.client.rpc('upsert_live_location', params: {
            'p_user_id': userId, 'p_business_id': businessId,
            'p_latitude': position.latitude, 'p_longitude': position.longitude, 'p_gps_enabled': true,
          });
        } catch (e) {
          print('Failed to write live location: $e');
        }
      }

      if (service is AndroidServiceInstance && await service.isForegroundService()) {
        final now = DateTime.now();
        final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        service.setForegroundNotificationInfo(title: 'Tracking Active', content: 'Last location saved at $timeString');
      }
    } catch (e) {
      print("Error fetching location: $e");
    }
  });
}