import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_monitor_screen.dart';

class UserTracksScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserTracksScreen({Key? key, required this.userId, required this.userName}) : super(key: key);

  String _formatDate(DateTime d) => "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
  String _formatTime(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  Future<void> _showSelfies(BuildContext context, Map<String, dynamic> session) async {
    final supabase = Supabase.instance.client;
    final startPath = session['start_selfie_path'] as String?;
    final stopPath = session['stop_selfie_path'] as String?;
    final autoStopped = session['auto_stopped'] == true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selfies'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<String?>>(
            future: Future.wait([
              if (startPath != null) supabase.storage.from('selfies').createSignedUrl(startPath, 3600) else Future.value(null),
              if (stopPath != null) supabase.storage.from('selfies').createSignedUrl(stopPath, 3600) else Future.value(null),
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
              }
              final startUrl = snapshot.data![0];
              final stopUrl = snapshot.data!.length > 1 ? snapshot.data![1] : null;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _selfieRow('Start', startUrl),
                  const SizedBox(height: 16),
                  _selfieRow('Stop', stopUrl, fallback: autoStopped ? 'Auto-stopped after 12 hours — no selfie taken' : 'Not available'),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _selfieRow(String label, String? url, {String fallback = 'Not available'}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, height: 180, fit: BoxFit.cover),
          )
        else
          SizedBox(
            height: 100,
            child: Center(child: Text(fallback, style: TextStyle(color: Colors.grey[600]))),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(title: Text('$userName\'s Tracks')),
      backgroundColor: Colors.grey[100],
      body: FutureBuilder(
        future: supabase
            .from('sessions')
            .select()
            .eq('user_id', userId)
            .order('start_time', ascending: false),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return Center(child: Text("$userName hasn't recorded any tracks yet."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index] as Map<String, dynamic>;
              final sessionId = session['session_id'] as String;
              final start = DateTime.parse(session['start_time']);
              final endRaw = session['end_time'] as String?;
              final end = endRaw != null ? DateTime.parse(endRaw) : null;
              final autoStopped = session['auto_stopped'] == true;

              String startStr = "${_formatDate(start)} at ${_formatTime(start)}";
              String durationStr;
              String endStr;

              if (end != null) {
                final duration = end.difference(start);
                durationStr = "${duration.inHours}h ${duration.inMinutes.remainder(60)}m worked";
                endStr = _formatTime(end);
                if (start.day != end.day || start.month != end.month || start.year != end.year) {
                  endStr = "${_formatDate(end)} at $endStr";
                }
              } else {
                durationStr = "In progress";
                endStr = "—";
              }

              return Card(
                elevation: 4,
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- MAP PREVIEW SECTION ---
                    SizedBox(
                      height: 130,
                      width: double.infinity,
                      child: FutureBuilder(
                        future: supabase
                            .from('location_tracks')
                            .select('latitude, longitude')
                            .eq('session_id', sessionId)
                            .order('timestamp', ascending: true),
                        builder: (context, AsyncSnapshot<List<dynamic>> pointsSnap) {
                          final points = pointsSnap.data ?? [];
                          final route = points.map((p) => LatLng(p['latitude'], p['longitude'])).toList();

                          return InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => MapMonitorScreen(userId: userId, sessionId: sessionId)),
                            ),
                            child: IgnorePointer(
                              child: route.isEmpty
                                  ? Container(color: Colors.grey[200])
                                  : FlutterMap(
                                      options: MapOptions(
                                        initialCenter: route.first,
                                        initialZoom: 13.0,
                                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.example.attendance_tracker',
                                        ),
                                        PolylineLayer(polylines: [Polyline(points: route, color: Colors.blue, strokeWidth: 4.0)]),
                                      ],
                                    ),
                            ),
                          );
                        },
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
                              Text(durationStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                              if (autoStopped)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(6)),
                                  child: const Text('Auto-stopped (12h)', style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
                                ),
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
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                  label: const Text('View Selfies'),
                                  onPressed: () => _showSelfies(context, session),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.map_outlined, size: 18),
                                  label: const Text('View Route'),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => MapMonitorScreen(userId: userId, sessionId: sessionId)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}