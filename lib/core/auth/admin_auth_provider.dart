import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleSignInOutcome {
  final AdminAuthResult? existingAdmin; // non-null = returning admin, straight to dashboard
  final String email;
  final String displayName;
  GoogleSignInOutcome({this.existingAdmin, required this.email, required this.displayName});
}

abstract class AdminAuthProvider {
  /// Starts signup — Supabase sends a confirmation OTP to this email.
  /// No session/account is usable yet until confirmSignup succeeds.
  Future<void> signUp({required String email, required String password});

  /// Confirms the OTP from signup, then creates the business + admin row.
  Future<AdminAuthResult> confirmSignup({
    required String email,
    required String otp,
    String? businessName,
    String? adminInviteCode, // if set, joins that business instead of creating one
  });

  /// Everyday login — no OTP involved.
  Future<AdminAuthResult> signIn({required String email, required String password});

  /// Returns the resolved admin directly, or null on first-time sign-in
  /// with no business yet — no stream/redirect involved with the native
  /// google_sign_in flow.
  Future<GoogleSignInOutcome> signInWithGoogle(); // replaces the old nullable-AdminAuthResult version

  Stream<AuthState> get authStateChanges;
  Future<AdminAuthResult?> resolveAdminForCurrentSession();
  Future<AdminAuthResult> createBusinessForCurrentSession(String businessName, String adminName);

  /// Signed-in account joins an existing business using an admin invite code.
  Future<AdminAuthResult> joinBusinessForCurrentSession(String inviteCode, String adminName);

  Future<void> signOut();
}

class AdminAuthResult {
  final String adminId;
  final String businessId;
  final String email;
  AdminAuthResult({required this.adminId, required this.businessId, required this.email});
}