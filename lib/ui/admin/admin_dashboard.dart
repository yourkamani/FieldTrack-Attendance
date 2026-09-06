import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_users_screen.dart';
import 'notifications_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  final List<String> roles = const ['driver', 'master', 'blaster', 'operator'];

  @override
  Widget build(BuildContext context) {

    final unreadStream = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.where((r) => r['is_read'] == false).length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          StreamBuilder<int>(
            stream: unreadStream,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: roles.length,
        itemBuilder: (context, index) {
          final role = roles[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.work, color: Colors.white),
              ),
              title: Text(role.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: const Text('Tap to view personnel'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RoleUsersScreen(role: role)
                ));
              },
            ),
          );
        },
      ),
    );
  }
}