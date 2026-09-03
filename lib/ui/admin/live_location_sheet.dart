import 'package:flutter/material.dart';
import '../../core/live_location_service.dart';

class LiveLocationSheet extends StatelessWidget {
  final String userId;
  final String userName;
  const LiveLocationSheet({Key? key, required this.userId, required this.userName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: LiveLocationService.watch(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Loading…')],
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return const Text('No location data yet for this user.');
          }

          final updatedAt = DateTime.parse(data['updated_at']);
          final isStale = DateTime.now().difference(updatedAt) > const Duration(minutes: 3);
          final gpsEnabled = data['gps_enabled'] == true;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$userName — Live Location', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (!gpsEnabled)
                const Column(children: [
                  Icon(Icons.location_off, color: Colors.orange, size: 40),
                  SizedBox(height: 8),
                  Text('Location is turned off on this device.'),
                ])
              else if (isStale)
                const Column(children: [
                  Icon(Icons.signal_wifi_off, color: Colors.grey, size: 40),
                  SizedBox(height: 8),
                  Text('No recent update — device may be offline or not tracking.'),
                ])
              else
                Column(children: [
                  const Icon(Icons.location_on, color: Colors.green, size: 40),
                  const SizedBox(height: 8),
                  Text('Lat: ${data['latitude']}, Lng: ${data['longitude']}'),
                ]),
              const SizedBox(height: 4),
              Text('Last updated: $updatedAt', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          );
        },
      ),
    );
  }
}