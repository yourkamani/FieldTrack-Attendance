import 'package:supabase_flutter/supabase_flutter.dart';

class SB {
  static SupabaseClient get client => Supabase.instance.client;
}