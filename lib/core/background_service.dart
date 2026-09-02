import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';

  // The UI screen generates the session id + start time BEFORE calling
  // service.startService(), so the selfie rows and the location rows
  // always share the same session_id. Fall back to a fresh id only if
  // something upstream forgot to set it, so tracking still works.
  final sessionId = prefs.getString('current_session_id') ?? DateTime.now().millisecondsSinceEpoch.toString();
  final sessionStartRaw = prefs.getString('current_session_start');
  final sessionStart = sessionStartRaw != null ? DateTime.parse(sessionStartRaw) : DateTime.now();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    // --- 12-HOUR AUTO-STOP (no selfie required for this path) ---
    if (DateTime.now().difference(sessionStart) >= kMaxSessionDuration) {
      timer.cancel();

      await DatabaseHelper.instance.updateSessionAutoStop(
        sessionId: sessionId,
        endTime: DateTime.now().toIso8601String(),
      );

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'Tracking Auto-Stopped',
            content: 'Reached the 12-hour tracking limit.',
          );
        }
      }

      // Let the UI know (in case the app is open) so it can reset its
      // button state and clear the stale session id without a selfie.
      await prefs.remove('current_session_id');
      await prefs.remove('current_session_start');

      service.stopSelf();
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'Tracking Paused',
            content: 'Please turn on GPS to resume tracking.',
          );
        }
      }
      return;
    }

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

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          final now = DateTime.now();
          final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

          service.setForegroundNotificationInfo(
            title: 'Tracking Active',
            content: 'Last location saved at $timeString',
          );
        }
      }
    } catch (e) {
      print("Error fetching location: $e");
    }
  });
}