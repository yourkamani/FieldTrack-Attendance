import 'supabase_client.dart';

class DataRetentionService {
  static Future<void> deleteDataBefore(DateTime cutoff, String businessId) async {
    // 1. Find sessions about to be deleted, to clean up their selfies first —
    //    once the row is gone we lose the path needed to find the file.
    final sessions = await SB.client
        .from('sessions')
        .select('start_selfie_path, stop_selfie_path')
        .eq('business_id', businessId)
        .lt('start_time', cutoff.toIso8601String())
        .not('end_time', 'is', null);

    final paths = <String>[];
    for (final s in sessions) {
      if (s['start_selfie_path'] != null) paths.add(s['start_selfie_path']);
      if (s['stop_selfie_path'] != null) paths.add(s['stop_selfie_path']);
    }
    if (paths.isNotEmpty) {
      await SB.client.storage.from('selfies').remove(paths);
    }

    // 2. Now remove the DB rows via the RPC.
    await SB.client.rpc('delete_data_before', params: {'cutoff': cutoff.toIso8601String()});
  }
}