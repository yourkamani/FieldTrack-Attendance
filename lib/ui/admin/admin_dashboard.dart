import 'package:flutter/material.dart';
import 'role_users_screen.dart'; // We will create this next

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  final List<String> roles = const ['driver', 'master', 'blaster', 'operator'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
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