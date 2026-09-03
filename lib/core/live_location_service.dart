import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLocationService {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> fetchLatest(String userId) {
    return _supabase.from('live_locations').select().eq('user_id', userId).maybeSingle();
  }

  static Stream<Map<String, dynamic>?> watch(String userId) {
    return _supabase
        .from('live_locations')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }
}