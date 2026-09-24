import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import 'admin_auth_provider.dart';

class SupabaseOtpAdminAuthProvider implements AdminAuthProvider {
  @override
  Future<void> signUp({required String email, required String password}) async {
    await SB.client.auth.signUp(email: email, password: password);
    // Supabase sends the confirmation OTP automatically here — nothing
    // else to trigger.
  }

  @override
  Future<AdminAuthResult> confirmSignup({
    required String email,
    required String otp,
    required String businessName,
  }) async {
    final res = await SB.client.auth.verifyOTP(email: email, token: otp, type: OtpType.signup);
    if (res.user == null) throw Exception('Invalid or expired code');

    final result = await SB.client
        .rpc('create_business_and_admin', params: {'business_name': businessName})
        .single();

    return AdminAuthResult(adminId: result['admin_id'], businessId: result['business_id'], email: email);
  }

  @override
  Future<AdminAuthResult> signIn({required String email, required String password}) async {
    final res = await SB.client.auth.signInWithPassword(email: email, password: password);
    if (res.user == null) throw Exception('Login failed');

    final admin = await SB.client.from('admins').select().eq('auth_user_id', res.user!.id).single();
    return AdminAuthResult(adminId: admin['id'], businessId: admin['business_id'], email: email);
  }

  @override
  Future<void> signInWithGoogle() async {
    await SB.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback',
    );
  }

  @override
  Stream<AuthState> get authStateChanges => SB.client.auth.onAuthStateChange;

  @override
  Future<AdminAuthResult?> resolveAdminForCurrentSession() async {
    final user = SB.client.auth.currentUser;
    if (user == null) throw Exception('No active session');

    final admin = await SB.client.from('admins').select().eq('auth_user_id', user.id).maybeSingle();
    if (admin == null) return null;

    return AdminAuthResult(adminId: admin['id'], businessId: admin['business_id'], email: user.email ?? '');
  }

  @override
  Future<AdminAuthResult> createBusinessForCurrentSession(String businessName) async {
    final user = SB.client.auth.currentUser;
    if (user == null) throw Exception('No active session');

    final result = await SB.client
        .rpc('create_business_and_admin', params: {'business_name': businessName})
        .single();

    return AdminAuthResult(adminId: result['admin_id'], businessId: result['business_id'], email: user.email ?? '');
  }

  @override
  Future<void> signOut() => SB.client.auth.signOut();
}