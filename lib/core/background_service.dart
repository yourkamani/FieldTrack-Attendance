import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart'; // ADDED for notification updates
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_tracking', 
    'Location Tracking',
    description: 'This channel is used for background location tracking.',
    importance: Importance.low, 
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // ONLY CREATE THE CHANNEL (No initialization needed!)
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
Future<bool> onIosBackground(ServiceInstance service) async { return true; }

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';
  final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      // Optional: Update notification to warn user if they turned GPS off mid-trip
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

      // Your existing SQLite logic
      await DatabaseHelper.instance.insertLocation({
        'user_id': userId,
        'session_id': sessionId,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // --- NEW: DYNAMIC NOTIFICATION UPDATE ---
      // Updates the foreground notification text with the latest sync time
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