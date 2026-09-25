import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/admin_auth_provider.dart';
import '../../core/auth/supabase_otp_admin_auth_provider.dart';
import '../../core/fcm_service.dart';
import 'admin_dashboard.dart';
import 'admin_signup_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);
  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final AdminAuthProvider _auth = SupabaseOtpAdminAuthProvider();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool loading = false;

  Future<String?> _promptBusinessName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("You're new here"),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Business Name')),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (emailCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) return;
    setState(() => loading = true);
    try {
      final result = await _auth.signIn(email: emailCtrl.text.trim(), password: passwordCtrl.text);
      await _finishLogin(result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => loading = true);
    try {
      final outcome = await _auth.signInWithGoogle();

      if (outcome.existingAdmin != null) {
        await _finishLogin(outcome.existingAdmin!);
      } else if (mounted) {
        final businessName = await _promptBusinessName();
        if (businessName != null && businessName.isNotEmpty) {
          final created = await _auth.createBusinessForCurrentSession(businessName, outcome.displayName);
          await _finishLogin(created);
        } else {
          await _auth.signOut();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _finishLogin(AdminAuthResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', result.adminId);
    await prefs.setString('business_id', result.businessId);
    await prefs.setString('role', 'admin');

    FcmService.init(ownerType: 'admin', ownerId: result.adminId, businessId: result.businessId)
        .catchError((e) => debugPrint('FCM init failed: $e'));

    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AdminDashboard()), (r) => false);
    }
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
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: passwordCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _login,
                    child: const Text('LOGIN'),
                  ),
            const SizedBox(height: 16),
            const Text('or', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: loading ? null : _signInWithGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSignupScreen())),
              child: const Text('New business? Sign up'),
            ),
          ],
        ),
      ),
    );
  }
}