import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin/admin_dashboard.dart';
import '../../core/fcm_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);

  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool loading = false;

  Future<void> _adminLogin() async {
    setState(() => loading = true);
    final supabase = Supabase.instance.client;

    try {
      final authResponse = await supabase.auth.signInWithPassword(
        email: usernameCtrl.text, // now expects an email
        password: passwordCtrl.text,
      );

      if (authResponse.user != null) {
        final adminRow = await supabase
            .from('admins')
            .select()
            .eq('auth_user_id', authResponse.user!.id)
            .maybeSingle();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', adminRow?['id'] ?? authResponse.user!.id);
        await prefs.setString('role', 'admin');

        FcmService.init(ownerType: 'admin', ownerId: adminRow?['id'] ?? authResponse.user!.id)
            .catchError((e) => debugPrint('FCM init failed: $e'));

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid login')));
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 30),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _adminLogin,
                    child: const Text('LOGIN AS ADMIN'),
                  ),
          ],
        ),
      ),
    );
  }
}