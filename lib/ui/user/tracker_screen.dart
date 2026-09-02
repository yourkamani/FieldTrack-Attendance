import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/sync_service.dart';
import '../../core/database_helper.dart';
import '../../core/selfie_service.dart';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({Key? key}) : super(key: key);

  @override
  _TrackerScreenState createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  bool isTracking = false;
  bool _busy = false; // true while a selfie/permission flow is in progress

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();

    // If the service isn't running but we still have a leftover session id
    // in prefs, the background service auto-stopped (12h cap) while this
    // screen wasn't around to react — just clean up and push the sync.
    if (!running) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('current_session_id') != null) {
        await prefs.remove('current_session_id');
        await prefs.remove('current_session_start');
        SyncService().syncOfflineData();
      }
    }

    setState(() => isTracking = running);
  }

  Future<void> _showSettingsDialog(String title, String message, VoidCallback onConfirm) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleTracking() async {
    if (_busy) return;

    if (isTracking) {
      await _stopTracking();
    } else {
      await _startTracking();
    }
  }

  // -------------------------------------------------------------------
  // START
  // -------------------------------------------------------------------
  Future<void> _startTracking() async {
    final service = FlutterBackgroundService();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _showSettingsDialog(
        'Location is Disabled',
        'Please turn on your device GPS/Location Services to start tracking.',
        () => Geolocator.openLocationSettings(),
      );
      return;
    }

    await Permission.notification.request();

    var foregroundStatus = await Permission.locationWhenInUse.request();
    if (!foregroundStatus.isGranted) {
      await _showSettingsDialog(
        'Permission Required',
        'Location permission is required to start tracking.',
        () => openAppSettings(),
      );
      return;
    }

    var backgroundStatus = await Permission.locationAlways.request();
    if (!backgroundStatus.isGranted) {
      await _showSettingsDialog(
        'Background Location Required',
        'To track your route accurately even when the app is closed, please select "Allow all the time" in the App Settings.',
        () => openAppSettings(),
      );
      return;
    }

    var cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      await _showSettingsDialog(
        'Camera Permission Required',
        'A start selfie is required before tracking begins. Please allow camera access.',
        () => openAppSettings(),
      );
      return;
    }

    setState(() => _busy = true);

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final startTime = DateTime.now();

    final selfiePath = await SelfieService.captureSelfie(sessionId: sessionId, type: 'start');
    if (selfiePath == null) {
      setState(() => _busy = false);
      _showSnack('A selfie is required to start tracking.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';

    await DatabaseHelper.instance.insertSessionStart({
      'session_id': sessionId,
      'user_id': userId,
      'start_time': startTime.toIso8601String(),
      'start_selfie_path': selfiePath,
      'auto_stopped': 0,
      'synced': 0,
    });

    // The background service reads these to keep using the SAME
    // session_id/start_time as this screen (and to know when 12h is up).
    await prefs.setString('current_session_id', sessionId);
    await prefs.setString('current_session_start', startTime.toIso8601String());

    await service.startService();
    SyncService().syncOfflineData();

    setState(() {
      isTracking = true;
      _busy = false;
    });
  }

  // -------------------------------------------------------------------
  // STOP (manual — selfie required)
  // -------------------------------------------------------------------
  Future<void> _stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('current_session_id');

    if (sessionId == null) {
      // Shouldn't normally happen, but don't leave the UI stuck.
      FlutterBackgroundService().invoke("stopService");
      setState(() => isTracking = false);
      return;
    }

    var cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _showSnack('Camera permission is required to take the stop selfie.');
      return;
    }

    setState(() => _busy = true);

    final selfiePath = await SelfieService.captureSelfie(sessionId: sessionId, type: 'stop');
    if (selfiePath == null) {
      setState(() => _busy = false);
      _showSnack('A selfie is required to stop tracking. Please try again.');
      return;
    }

    await DatabaseHelper.instance.updateSessionStop(
      sessionId: sessionId,
      endTime: DateTime.now().toIso8601String(),
      stopSelfiePath: selfiePath,
    );

    FlutterBackgroundService().invoke("stopService");
    await prefs.remove('current_session_id');
    await prefs.remove('current_session_start');

    SyncService().syncOfflineData();

    setState(() {
      isTracking = false;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Tracker')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isTracking ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 50),
                shape: const CircleBorder(),
              ),
              onPressed: _busy ? null : _toggleTracking,
              child: _busy
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white))
                  : Text(
                      isTracking ? 'STOP' : 'START',
                      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              isTracking
                  ? 'A selfie will be required to stop.\nTracking auto-stops after 12 hours.'
                  : 'A quick selfie is required to start tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}