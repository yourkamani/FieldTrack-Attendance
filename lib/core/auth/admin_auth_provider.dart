import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AdminAuthProvider {
  /// Starts signup — Supabase sends a confirmation OTP to this email.
  /// No session/account is usable yet until confirmSignup succeeds.
  Future<void> signUp({required String email, required String password});

  /// Confirms the OTP from signup, then creates the business + admin row.
  Future<AdminAuthResult> confirmSignup({
    required String email,
    required String otp,
    required String businessName,
  });

  /// Everyday login — no OTP involved.
  Future<AdminAuthResult> signIn({required String email, required String password});

  Future<void> signInWithGoogle();
  Stream<AuthState> get authStateChanges;

  /// Used after a Google redirect completes — null means first-time
  /// Google sign-in with no business yet.
  Future<AdminAuthResult?> resolveAdminForCurrentSession();
  Future<AdminAuthResult> createBusinessForCurrentSession(String businessName);

  Future<void> signOut();
}

class AdminAuthResult {
  final String adminId;
  final String businessId;
  final String email;
  AdminAuthResult({required this.adminId, required this.businessId, required this.email});
}