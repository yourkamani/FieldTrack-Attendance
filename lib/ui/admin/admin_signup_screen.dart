import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/admin_auth_provider.dart';
import '../../core/auth/supabase_otp_admin_auth_provider.dart';
import '../../core/fcm_service.dart';
import 'admin_dashboard.dart';

enum _Stage { details, otp }

class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({Key? key}) : super(key: key);
  @override
  _AdminSignupScreenState createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  final AdminAuthProvider _auth = SupabaseOtpAdminAuthProvider();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final businessNameCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  _Stage stage = _Stage.details;
  bool loading = false;

  Future<void> _submitDetails() async {
    if (emailCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty || businessNameCtrl.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      await _auth.signUp(email: emailCtrl.text.trim(), password: passwordCtrl.text);
      setState(() => stage = _Stage.otp);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _confirm() async {
    if (otpCtrl.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final result = await _auth.confirmSignup(
        email: emailCtrl.text.trim(),
        otp: otpCtrl.text.trim(),
        businessName: businessNameCtrl.text.trim(),
      );

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
      appBar: AppBar(title: const Text('Create Business Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (stage == _Stage.details) ...[
              TextField(controller: businessNameCtrl,
                decoration: const InputDecoration(labelText: 'Business Name', border: OutlineInputBorder())),
              const SizedBox(height: 15),
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
                      onPressed: _submitDetails,
                      child: const Text('CONTINUE'),
                    ),
            ],
            if (stage == _Stage.otp) ...[
              Text('Enter the code sent to ${emailCtrl.text.trim()}', textAlign: TextAlign.center),
              const SizedBox(height: 15),
              TextField(controller: otpCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      onPressed: _confirm,
                      child: const Text('VERIFY & CREATE BUSINESS'),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}