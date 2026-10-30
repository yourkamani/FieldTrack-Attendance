import 'dart:async';
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
  final inviteCtrl = TextEditingController();
  _Stage stage = _Stage.details;
  bool loading = false;
  bool resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    inviteCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _submitDetails() async {
    final joining = inviteCtrl.text.trim().isNotEmpty;
    if (emailCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) return;
    if (!joining && businessNameCtrl.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      await _auth.signUp(email: emailCtrl.text.trim(), password: passwordCtrl.text);
      setState(() => stage = _Stage.otp);
      _startCooldown();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    setState(() => resending = true);
    try {
      await _auth.signUp(email: emailCtrl.text.trim(), password: passwordCtrl.text); // re-sends a fresh code
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New code sent')));
      _startCooldown();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => resending = false);
  }

  Future<void> _confirm() async {
    if (otpCtrl.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final result = await _auth.confirmSignup(
        email: emailCtrl.text.trim(),
        otp: otpCtrl.text.trim(),
        businessName: businessNameCtrl.text.trim(),
        adminInviteCode: inviteCtrl.text.trim(),
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
                decoration: const InputDecoration(labelText: 'Business Name (new business)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text('— or join an existing business —', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(controller: inviteCtrl, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Admin invite code (optional)', border: OutlineInputBorder())),
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
                      child: Text(inviteCtrl.text.trim().isNotEmpty ? 'VERIFY & JOIN BUSINESS' : 'VERIFY & CREATE BUSINESS'),
                    ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: (resending || _resendCooldown > 0) ? null : _resendOtp,
                child: resending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_resendCooldown > 0 ? 'Resend code (${_resendCooldown}s)' : 'Resend code'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}