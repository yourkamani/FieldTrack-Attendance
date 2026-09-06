import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/notification_model.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stream = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(NotificationModel.fromMap).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<NotificationModel>>(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!;
          if (items.isEmpty) return const Center(child: Text('No notifications yet.'));

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final n = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: n.isRead ? null : Colors.blue[50],
                child: ListTile(
                  leading: Icon(
                    n.type == 'location_off' ? Icons.location_off : Icons.notifications,
                    color: n.type == 'location_off' ? Colors.orange : Colors.blue,
                  ),
                  title: Text(n.message),
                  subtitle: Text('${n.userPhone} • ${n.createdAt}'),
                  onTap: () async {
                    if (!n.isRead) {
                      await Supabase.instance.client
                          .from('notifications')
                          .update({'is_read': true}).eq('id', n.id);
                    }
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(n.userName),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phone: ${n.userPhone}'),
                            const SizedBox(height: 8),
                            Text(n.message),
                            const SizedBox(height: 8),
                            Text('At: ${n.createdAt}', style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}