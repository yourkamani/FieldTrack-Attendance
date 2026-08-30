import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/sync_service.dart';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({Key? key}) : super(key: key);

  @override
  _TrackerScreenState createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  bool isTracking = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    final service = FlutterBackgroundService();
    isTracking = await service.isRunning();
    setState(() {});
  }

  Future<void> _showSettingsDialog(String title, String message, VoidCallback onConfirm) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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

  Future<void> _toggleTracking() async {
    final service = FlutterBackgroundService();
    
    // STOP TRACKING
    if (isTracking) {
      service.invoke("stopService");
      SyncService().syncOfflineData();
      setState(() => isTracking = false);
      return;
    } 
    
    // START TRACKING CHECKS
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

    // Start the Background Service
    await service.startService();
    setState(() => isTracking = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Tracker')),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isTracking ? Colors.red : Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 50),
            shape: const CircleBorder()
          ),
          onPressed: _toggleTracking,
          child: Text(isTracking ? 'STOP' : 'START', 
            style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}