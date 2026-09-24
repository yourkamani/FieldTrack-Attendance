import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'core/background_service.dart';
import 'core/sync_service.dart';
import 'core/fcm_service.dart';
import 'ui/auth/login_screen.dart';
import 'ui/auth/invite_code_screen.dart';
import 'ui/user/tracker_screen.dart';
import 'ui/admin/admin_dashboard.dart';
import 'ui/admin/admin_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await FlutterLocalNotificationsPlugin().initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  const alertChannel = AndroidNotificationChannel('alerts', 'Alerts',
      description: 'Location-off and other admin alerts.', importance: Importance.high);
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alertChannel);

  await Supabase.initialize(url: 'https://ctfhrpohgqqvbdxglebw.supabase.co', anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0ZmhycG9oZ3FxdmJkeGdsZWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNjA5MDMsImV4cCI6MjEwNTczNjkwM30.k-kGhWvH3k1Iet6cR6zrn7kUbuGnGaYP64KLMMAkLb8');

  await initializeService();
  SyncService().startListening();

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  final businessId = prefs.getString('business_id');
  final role = prefs.getString('role');

  Widget initialScreen;

  if (role == 'admin') {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && userId != null && businessId != null) {
      initialScreen = const AdminDashboard();
      FcmService.init(ownerType: 'admin', ownerId: userId, businessId: businessId).catchError((e) => debugPrint('$e'));
    } else {
      await prefs.clear();
      initialScreen = const AdminLoginScreen();
    }
  } else if (userId != null && userId.isNotEmpty && businessId != null) {
    initialScreen = const TrackerScreen();
    FcmService.init(ownerType: 'user', ownerId: userId, businessId: businessId).catchError((e) => debugPrint('$e'));
  } else {
    initialScreen = const LoginScreen();
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({Key? key, required this.initialScreen}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Tracker App', theme: ThemeData(primarySwatch: Colors.blue), home: initialScreen);
  }
}