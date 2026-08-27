import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapMonitorScreen extends StatefulWidget {
  final String userId;
  final String sessionId;

  const MapMonitorScreen({Key? key, required this.userId, required this.sessionId}) : super(key: key);

  @override
  _MapMonitorScreenState createState() => _MapMonitorScreenState();
}

class _MapMonitorScreenState extends State<MapMonitorScreen> {
  final _supabase = Supabase.instance.client;
  List<LatLng> routePoints = [];
  List<Marker> markers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRouteData();
  }

  Future<void> _fetchRouteData() async {
    final response = await _supabase
        .from('location_tracks')
        .select()
        .eq('user_id', widget.userId)
        .eq('session_id', widget.sessionId)
        .order('timestamp', ascending: true);

    List<LatLng> points = [];
    DateTime? haltStartTime;
    LatLng? potentialHalt;
    DateTime? lastTime;

    for (var i = 0; i < response.length; i++) {
      var row = response[i];
      LatLng currentLoc = LatLng(row['latitude'], row['longitude']);
      DateTime currentTime = DateTime.parse(row['timestamp']);
      points.add(currentLoc);

      // 1. GAP ALERT: Missing location for > 5 minutes
      if (lastTime != null && currentTime.difference(lastTime).inMinutes > 5) {
        markers.add(Marker(
          point: currentLoc,
          child: const Icon(Icons.warning, color: Colors.red, size: 30),
        ));
      }
      lastTime = currentTime;

      // 2. HALT ALERT: Stopped for > 1 hour
      if (potentialHalt == null) {
        potentialHalt = currentLoc;
        haltStartTime = currentTime;
      } else {
        // Rough distance logic (Manhattan distance for speed)
        double distance = (currentLoc.latitude - potentialHalt.latitude).abs() + 
                          (currentLoc.longitude - potentialHalt.longitude).abs();
        
        if (distance < 0.001) { // Same rough area
          if (currentTime.difference(haltStartTime!).inHours >= 1) {
            markers.add(Marker(
              point: currentLoc,
              child: const Icon(Icons.stop_circle, color: Colors.orange, size: 30),
            ));
          }
        } else { // Moved away, reset halt monitor
          potentialHalt = currentLoc;
          haltStartTime = currentTime;
        }
      }
    }

    setState(() {
      routePoints = points;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Travel Map (Free OSM)')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: routePoints.isNotEmpty ? routePoints.first : const LatLng(0, 0),
          initialZoom: 14.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.your.app', // REQUIRED by OSM policy
          ),
          PolylineLayer(
            polylines: [
              Polyline(points: routePoints, color: Colors.blue, strokeWidth: 5.0),
            ],
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}