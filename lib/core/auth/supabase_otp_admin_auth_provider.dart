import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../invite_service.dart';
import 'admin_auth_provider.dart';

class SupabaseOtpAdminAuthProvider implements AdminAuthProvider {
  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: '234756730500-lpp8qjvrkilj8184asqnkds9froh7kue.apps.googleusercontent.com',
    );
    _googleInitialized = true;
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    await SB.client.auth.signUp(email: email, password: password);
  }

  @override
  Future<AdminAuthResult> confirmSignup({
    required String email,
    required String otp,
    String? businessName,
    String? adminInviteCode,
  }) async {
    final res = await SB.client.auth.verifyOTP(email: email, token: otp, type: OtpType.signup);
    if (res.user == null) throw Exception('Invalid or expired code');

    if (adminInviteCode != null && adminInviteCode.trim().isNotEmpty) {
      final joined = await InviteService.redeemAdminInvite(adminInviteCode, name: email.split('@').first);
      return AdminAuthResult(adminId: joined['admin_id'], businessId: joined['business_id'], email: email);
    }

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
  Future<GoogleSignInOutcome> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) rethrow; // let caller decide how to handle cancel
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('No ID token from Google');

    final res = await SB.client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    if (res.user == null) throw Exception('Google sign-in failed');

    final admin = await SB.client.from('admins').select().eq('auth_user_id', res.user!.id).maybeSingle();
    final existing = admin == null
        ? null
        : AdminAuthResult(adminId: admin['id'], businessId: admin['business_id'], email: res.user!.email ?? '');

    return GoogleSignInOutcome(
      existingAdmin: existing,
      email: res.user!.email ?? account.email,
      displayName: account.displayName ?? (res.user!.email ?? '').split('@').first,
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
  Future<AdminAuthResult> createBusinessForCurrentSession(String businessName, String adminName) async {
    final user = SB.client.auth.currentUser;
    if (user == null) throw Exception('No active session');

    final result = await SB.client.rpc('create_business_and_admin', params: {
      'business_name': businessName,
      'admin_name': adminName,
    }).single();

    return AdminAuthResult(adminId: result['admin_id'], businessId: result['business_id'], email: user.email ?? '');
  }

  @override
  Future<AdminAuthResult> joinBusinessForCurrentSession(String inviteCode, String adminName) async {
    final user = SB.client.auth.currentUser;
    if (user == null) throw Exception('No active session');
    final joined = await InviteService.redeemAdminInvite(inviteCode, name: adminName);
    return AdminAuthResult(adminId: joined['admin_id'], businessId: joined['business_id'], email: user.email ?? '');
  }

  @override
  Future<void> signOut() => SB.client.auth.signOut();
}