import 'dart:io';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';

class SyncService {
  final _supabase = Supabase.instance.client;

  void startListening() {
    InternetConnectionChecker.instance.onStatusChange.listen((status) {
      if (status == InternetConnectionStatus.connected) syncOfflineData();
    });
  }

  Future<void> syncOfflineData() async {
    await _syncLocations();
    await _syncSessions();
  }

  Future<void> _syncLocations() async {
    final offlineLocations = await DatabaseHelper.instance.getUnsyncedLocations();
    if (offlineLocations.isEmpty) return;

    List<int> syncedIds = [];
    List<Map<String, dynamic>> uploadBatch = [];

    for (var loc in offlineLocations) {
      syncedIds.add(loc['id']);
      uploadBatch.add({
        'user_id': loc['user_id'], 'business_id': loc['business_id'], 'session_id': loc['session_id'],
        'latitude': loc['lat'], 'longitude': loc['lng'], 'timestamp': loc['timestamp'],
      });
    }

    try {
      await _supabase.from('location_tracks').insert(uploadBatch);
      await DatabaseHelper.instance.clearSyncedLocations(syncedIds);
    } catch (e) {
      print("Location sync failed: $e");
    }
  }

  Future<void> _syncSessions() async {
    final pending = await DatabaseHelper.instance.getUnsyncedSessions();

    for (final session in pending) {
      final sessionId = session['session_id'] as String;
      final userId = session['user_id'] as String;
      final businessId = session['business_id'] as String?;

      try {
        String? startStoragePath;
        String? stopStoragePath;

        final startPath = session['start_selfie_path'] as String?;
        if (startPath != null && File(startPath).existsSync()) {
          startStoragePath = await _uploadSelfie(userId, sessionId, 'start', startPath);
        }
        final stopPath = session['stop_selfie_path'] as String?;
        if (stopPath != null && File(stopPath).existsSync()) {
          stopStoragePath = await _uploadSelfie(userId, sessionId, 'stop', stopPath);
        }

        await _supabase.from('sessions').upsert({
          'session_id': sessionId, 'user_id': userId, 'business_id': businessId,
          'start_time': session['start_time'], 'end_time': session['end_time'],
          'start_selfie_path': startStoragePath, 'stop_selfie_path': stopStoragePath,
          'auto_stopped': session['auto_stopped'] == 1,
        }, onConflict: 'session_id');

        final isComplete = session['end_time'] != null;
        if (isComplete) {
          await DatabaseHelper.instance.markSessionSynced(sessionId);
          if (startPath != null) await File(startPath).delete().catchError((_) => File(startPath));
          if (stopPath != null) await File(stopPath).delete().catchError((_) => File(stopPath));
        }
      } catch (e) {
        print("Session sync failed for $sessionId: $e");
      }
    }
  }

  Future<String> _uploadSelfie(String userId, String sessionId, String type, String localPath) async {
    final storagePath = '$userId/${sessionId}_$type.jpg';
    try {
      await _supabase.storage.from('selfies').upload(storagePath, File(localPath),
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
    } on StorageException catch (e) {
      final exists = e.statusCode == '409' || e.message.toLowerCase().contains('already exists') || e.message.toLowerCase().contains('duplicate');
      if (exists) return storagePath;
      rethrow;
    }
    return storagePath;
  }
}