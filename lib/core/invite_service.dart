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

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}