import 'dart:math';
import 'supabase_client.dart';

class InviteService {
  static Future<String?> resolveBusinessId(String code) async {
    final row = await SB.client
        .from('invite_codes')
        .select('business_id')
        .eq('code', code)
        .eq('is_active', true)
        .maybeSingle();
    return row?['business_id'] as String?;
  }

  static Future<String> generateCode(String businessId) async {
    final code = _randomCode();
    await SB.client.from('invite_codes').insert({'business_id': businessId, 'code': code});
    return code;
  }

  static Future<String> resetCode(String codeId) async {
    final newCode = _randomCode();
    await SB.client.from('invite_codes').update({'code': newCode}).eq('id', codeId);
    return newCode;
  }

  /// Permanently deletes an employee invite code. Employees who already
  /// registered with it are unaffected; nobody new can use it.
  static Future<void> deleteCode(String codeId) async {
    final deleted = await SB.client.from('invite_codes').delete().eq('id', codeId).select();
    if (deleted.isEmpty) {
      throw Exception('Could not delete code (no permission). Run supabase/001_multi_admin_and_invites.sql.');
    }
  }

  // ---------------- Admin invites (multi-admin) ----------------

  /// Creates a single-use admin invite valid for 7 days. Returns the code.
  static Future<String> createAdminInvite() async {
    final code = await SB.client.rpc('create_admin_invite');
    return code as String;
  }

  static Future<void> deleteAdminInvite(String inviteId) async {
    final deleted = await SB.client.from('admin_invites').delete().eq('id', inviteId).select();
    if (deleted.isEmpty) throw Exception('Could not delete invite');
  }

  /// Signed-in account joins an existing business as admin.
  /// Returns {admin_id, business_id}.
  static Future<Map<String, dynamic>> redeemAdminInvite(String code, {String? name}) async {
    final res = await SB.client
        .rpc('redeem_admin_invite', params: {'p_code': code.trim().toUpperCase(), 'p_admin_name': name})
        .single();
    return Map<String, dynamic>.from(res);
  }

  static Future<void> removeAdmin(String adminId) async {
    await SB.client.rpc('remove_admin', params: {'p_admin_id': adminId});
  }

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
