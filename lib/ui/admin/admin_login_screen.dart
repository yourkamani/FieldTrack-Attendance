import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/admin_auth_provider.dart';
import '../../core/auth/supabase_email_admin_auth_provider.dart';
import '../../core/fcm_service.dart';
import 'admin_dashboard.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);
  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final AdminAuthProvider _auth = SupabaseEmailAdminAuthProvider();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final businessNameCtrl = TextEditingController();
  bool isSignUp = false;
  bool loading = false;

  Future<void> _submit() async {
    setState(() => loading = true);
    try {
      final result = isSignUp
          ? await _auth.signUp(email: emailCtrl.text.trim(), password: passwordCtrl.text, businessName: businessNameCtrl.text.trim())
          : await _auth.signIn(email: emailCtrl.text.trim(), password: passwordCtrl.text);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', result.adminId);
      await prefs.setString('business_id', result.businessId);
      await prefs.setString('role', 'admin');

      FcmService.init(ownerType: 'admin', ownerId: result.adminId, businessId: result.businessId)
          .catchError((e) => debugPrint('FCM init failed: $e'));

      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AdminDashboard()), (r) => false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isSignUp ? 'Create Business Account' : 'Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSignUp) ...[
              TextField(controller: businessNameCtrl, decoration: const InputDecoration(labelText: 'Business Name', border: OutlineInputBorder())),
              const SizedBox(height: 15),
            ],
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 30),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _submit,
                    child: Text(isSignUp ? 'CREATE BUSINESS' : 'LOGIN'),
                  ),
            TextButton(
              onPressed: () => setState(() => isSignUp = !isSignUp),
              child: Text(isSignUp ? 'Already have a business? Log in' : 'New business? Create one'),
            ),
          ],
        ),
      ),
    );
  }
}