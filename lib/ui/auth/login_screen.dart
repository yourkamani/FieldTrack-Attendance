import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../user/tracker_screen.dart';
import 'admin_login_screen.dart';
import '../../core/fcm_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String role = 'driver'; // Default role
  bool loading = false;

  final List<String> roles = ['driver', 'master', 'blaster', 'operator'];

  Future<void> _login() async {
    if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    setState(() => loading = true);
    final supabase = Supabase.instance.client;
    
    try {
      final res = await supabase.from('users').upsert({
        'phone': phoneCtrl.text,
        'name': nameCtrl.text,
        'role': role,
      }, onConflict: 'phone').select().single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', res['id']);
      await prefs.setString('role', res['role']);

      // Don't let FCM issues block login navigation.
      FcmService.init(ownerType: 'user', ownerId: res['id'])
          .catchError((e) => debugPrint('FCM init failed: $e'));

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackerScreen()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => loading = false);
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
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Select Role'),
              items: roles.map((String r) {
                return DropdownMenuItem(value: r, child: Text(r.toUpperCase()));
              }).toList(),
              onChanged: (val) => setState(() => role = val!),
            ),
            const SizedBox(height: 30),
            loading 
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  onPressed: _login, 
                  child: const Text('LOGIN')
                ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
              },
              child: const Text('Admin Access', style: TextStyle(color: Colors.grey)),
            )
          ],
        ),
      ),
    );
  }
}