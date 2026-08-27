import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';

class SyncService {
  final _supabase = Supabase.instance.client;

  void startListening() {
    InternetConnectionChecker.instance.onStatusChange.listen((status) {
      if (status == InternetConnectionStatus.connected) {
        syncOfflineData();
      }
    });
  }


  Future<void> syncOfflineData() async {
    final offlineLocations = await DatabaseHelper.instance.getUnsyncedLocations();
    if (offlineLocations.isEmpty) return;

    List<int> syncedIds = [];
    List<Map<String, dynamic>> uploadBatch = [];

    for (var loc in offlineLocations) {
      syncedIds.add(loc['id']);
      uploadBatch.add({
        'user_id': loc['user_id'],
        'session_id': loc['session_id'],
        'latitude': loc['lat'],
        'longitude': loc['lng'],
        'timestamp': loc['timestamp'],
      });
    }

    try {
      await _supabase.from('location_tracks').insert(uploadBatch);
      await DatabaseHelper.instance.clearSyncedLocations(syncedIds);
    } catch (e) {
      print("Sync failed: $e");
    }
  }
}