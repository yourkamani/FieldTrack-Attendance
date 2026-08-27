import 'package:flutter/material.dart';
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
      body: FutureBuilder(
        future: supabase.from('location_tracks').select('session_id, timestamp').eq('user_id', userId).order('timestamp', ascending: false),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          // Group sessions and find the START date/time of each session
          Map<String, DateTime> sessionDates = {};
          
          for (var row in snapshot.data!) {
            String sId = row['session_id'];
            DateTime time = DateTime.parse(row['timestamp']);
            
            // Keep the earliest time for the session to show when they clicked "Start"
            if (!sessionDates.containsKey(sId) || time.isBefore(sessionDates[sId]!)) {
               sessionDates[sId] = time;
            }
          }
          
          // Sort the sessions so the most recent track is at the top
          List<MapEntry<String, DateTime>> sortedSessions = sessionDates.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          if (sortedSessions.isEmpty) {
            return Center(child: Text("$userName hasn't recorded any tracks yet.", style: const TextStyle(fontSize: 16)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: sortedSessions.length,
            itemBuilder: (context, index) {
              final session = sortedSessions[index];
              final date = session.value;
              
              // Format Date manually (e.g., "27/8/2026 at 10:05")
              final minute = date.minute.toString().padLeft(2, '0');
              final formattedDate = "${date.day}/${date.month}/${date.year}";
              final formattedTime = "${date.hour}:$minute";

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.map, color: Colors.white),
                  ),
                  title: Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('Started at $formattedTime'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MapMonitorScreen(userId: userId, sessionId: session.key)
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }
}