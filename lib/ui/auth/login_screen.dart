import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import '../user/tracker_screen.dart';
import 'invite_code_screen.dart';
import '../admin/admin_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneCtrl = TextEditingController();
  bool loading = false;

  Future<void> _continue() async {
    if (phoneCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your phone number')));
      return;
    }
    setState(() => loading = true);
    final phone = phoneCtrl.text.trim();

    try {
      final existing = await SB.client.from('users').select().eq('phone', phone).maybeSingle();
      final prefs = await SharedPreferences.getInstance();

      if (existing != null) {
        await prefs.setString('user_id', existing['id']);
        await prefs.setString('business_id', existing['business_id']);
        await prefs.setString('role', existing['role']);
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackerScreen()));
        }
      } else {
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InviteCodeScreen(phone: phone)));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personnel Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 30),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _continue,
                    child: const Text('CONTINUE'),
                  ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen())),
              child: const Text('Admin Access', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}