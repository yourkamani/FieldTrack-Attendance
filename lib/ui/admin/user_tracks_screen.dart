import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_monitor_screen.dart';

class UserTracksScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserTracksScreen({Key? key, required this.userId, required this.userName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(title: Text('$userName\'s Tracks')),
      backgroundColor: Colors.grey[100], // Slight background color to make cards pop
      body: FutureBuilder(
        // We now fetch latitude and longitude to draw the preview map
        future: supabase
            .from('location_tracks')
            .select('session_id, timestamp, latitude, longitude')
            .eq('user_id', userId)
            .order('timestamp', ascending: true),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          // Group all data points by session_id
          Map<String, List<Map<String, dynamic>>> sessionData = {};
          for (var row in snapshot.data!) {
            String sId = row['session_id'];
            if (!sessionData.containsKey(sId)) {
              sessionData[sId] = [];
            }
            sessionData[sId]!.add(row);
          }
          
          // Sort sessions so the most recent is at the top
          List<MapEntry<String, List<Map<String, dynamic>>>> sortedSessions = sessionData.entries.toList()
            ..sort((a, b) {
              DateTime timeA = DateTime.parse(a.value.first['timestamp']);
              DateTime timeB = DateTime.parse(b.value.first['timestamp']);
              return timeB.compareTo(timeA);
            });

          if (sortedSessions.isEmpty) {
            return Center(child: Text("$userName hasn't recorded any tracks yet."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: sortedSessions.length,
            itemBuilder: (context, index) {
              final session = sortedSessions[index];
              final pointsData = session.value;

              // 1. Calculate Times
              final start = DateTime.parse(pointsData.first['timestamp']);
              final end = DateTime.parse(pointsData.last['timestamp']);
              final duration = end.difference(start);

              // 2. Format Dates & Times
              String formatDate(DateTime d) => "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
              String formatTime(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

              String startStr = "${formatDate(start)} at ${formatTime(start)}";
              
              // Only show the End Date if it is different from the Start Date
              String endStr = formatTime(end);
              if (start.day != end.day || start.month != end.month || start.year != end.year) {
                endStr = "${formatDate(end)} at $endStr";
              }

              String durationStr = "${duration.inHours}h ${duration.inMinutes.remainder(60)}m worked";

              // 3. Extract Route Points for the Preview Map
              List<LatLng> route = pointsData
                  .map((p) => LatLng(p['latitude'], p['longitude']))
                  .toList();

              return Card(
                elevation: 4,
                clipBehavior: Clip.antiAlias, // Ensures the map respects the card's rounded corners
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MapMonitorScreen(userId: userId, sessionId: session.key)
                  )),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- MAP PREVIEW SECTION ---
                      SizedBox(
                        height: 130, // Small preview height
                        width: double.infinity,
                        child: IgnorePointer(
                          // IgnorePointer prevents the map from stealing scrolls from the ListView
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: route.isNotEmpty ? route.first : const LatLng(0, 0),
                              initialZoom: 13.0,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none), // Disable zooming/panning
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.attendance_tracker',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(points: route, color: Colors.blue, strokeWidth: 4.0),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // --- DETAILS SECTION ---
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  durationStr, 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                              ],
                            ),
                            const Divider(),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.play_circle_fill, color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Text("Start: $startStr"),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.stop_circle, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Text("End:   $endStr"),
                              ],
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}