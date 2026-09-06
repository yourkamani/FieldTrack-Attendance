import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  static final _supabase = Supabase.instance.client;

  static Future<void> updateUser({
    required String userId,
    required String name,
    required String role,
  }) async {
    await _supabase.from('users').update({
      'name': name,
      'role': role,
    }).eq('id', userId);
  }

  /// Deletes a user and every record tied to them, including their
  /// uploaded selfies in Storage.
  static Future<void> deleteUserCascade(String userId) async {
    // Storage first — list everything under this user's folder, then
    // remove by exact path. Bucket layout is '$userId/${sessionId}_type.jpg'.
    try {
      final files = await _supabase.storage.from('selfies').list(path: userId);
      if (files.isNotEmpty) {
        final paths = files.map((f) => '$userId/${f.name}').toList();
        await _supabase.storage.from('selfies').remove(paths);
      }
    } catch (e) {
      // Don't let a storage hiccup block the rest of the delete —
      // surface it, but keep going so the DB rows still get cleaned up.
      print('Failed to delete selfies for $userId: $e');
    }

    await _supabase.from('location_tracks').delete().eq('user_id', userId);
    await _supabase.from('sessions').delete().eq('user_id', userId);
    await _supabase.from('live_locations').delete().eq('user_id', userId);
    await _supabase.from('notifications').delete().eq('user_id', userId);
    await _supabase.from('device_tokens').delete().eq('owner_type', 'user').eq('owner_id', userId);
    await _supabase.from('users').delete().eq('id', userId);
  }
}