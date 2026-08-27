import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/background_service.dart';
import 'core/sync_service.dart';
import 'ui/auth/login_screen.dart';
import 'ui/user/tracker_screen.dart';
import 'ui/admin/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://tmoacgbszammuasaxapo.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtb2FjZ2JzemFtbXVhc2F4YXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3OTg1MzgsImV4cCI6MjEwMjM3NDUzOH0.NJxYtAyRXPMi8P7H-sClCOpWcBIhqGwz-6TvastkeUw',
  );

  await initializeService();
  SyncService().startListening();

  // CHECK LOGIN STATE
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  final role = prefs.getString('role');

  Widget initialScreen = const LoginScreen(); // Default to login

  // If user_id exists, bypass login
  if (userId != null && userId.isNotEmpty) {
    if (role == 'admin') {
      initialScreen = const AdminDashboard();
    } else {
      initialScreen = const TrackerScreen();
    }
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({Key? key, required this.initialScreen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracker App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialScreen, // Starts on the correct screen automatically
    );
  }
}