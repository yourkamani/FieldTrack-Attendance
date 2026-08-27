import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/sync_service.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // Make sure this is at the top of your file:
// import 'package:permission_handler/permission_handler.dart';

  Future<void> _toggleTracking() async {
    final service = FlutterBackgroundService();
    
    if (isTracking) {
      service.invoke("stopService");
      SyncService().syncOfflineData();
    } else {
      // 1. Request Notification Permission
      await Permission.notification.request();

      // 2. Request "While In Use" (Foreground) Location FIRST
      var foregroundStatus = await Permission.locationWhenInUse.request();
      
      if (foregroundStatus.isGranted) {
        // 3. Request "Allow All The Time" (Background) Location SECOND
        var backgroundStatus = await Permission.locationAlways.request();
        
        if (!backgroundStatus.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Warning: Background tracking will stop if you close the app.')),
          );
        }
        
        // Start the service regardless, it will at least work in the foreground
        await service.startService();
        
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to start tracking.')),
        );
        await openAppSettings(); // Take them to settings if they denied it
        return;
      }
    }
    
    setState(() => isTracking = !isTracking);
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