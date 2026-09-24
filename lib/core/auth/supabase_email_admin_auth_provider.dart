import '../supabase_client.dart';
import 'admin_auth_provider.dart';

class SupabaseEmailAdminAuthProvider implements AdminAuthProvider {
  @override
  Future<AdminAuthResult> signUp({
    required String email,
    required String password,
    required String businessName,
  }) async {
    final authRes = await SB.client.auth.signUp(email: email, password: password);
    final authUser = authRes.user;
    if (authUser == null) throw Exception('Signup failed');

    final business = await SB.client.from('businesses').insert({'name': businessName}).select().single();

    final admin = await SB.client.from('admins').insert({
      'auth_user_id': authUser.id,
      'business_id': business['id'],
      'username': email,
    }).select().single();

    return AdminAuthResult(adminId: admin['id'], businessId: business['id'], email: email);
  }

  @override
  Future<AdminAuthResult> signIn({required String email, required String password}) async {
    final authRes = await SB.client.auth.signInWithPassword(email: email, password: password);
    final authUser = authRes.user;
    if (authUser == null) throw Exception('Login failed');

    final admin = await SB.client.from('admins').select().eq('auth_user_id', authUser.id).single();
    return AdminAuthResult(adminId: admin['id'], businessId: admin['business_id'], email: email);
  }

  @override
  Future<void> signOut() => SB.client.auth.signOut();
}