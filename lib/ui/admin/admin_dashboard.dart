import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import 'role_users_screen.dart';
import 'notifications_screen.dart';
import '../shared/profile_screen.dart';
import 'invite_codes_screen.dart';
import 'data_retention_screen.dart';
import 'live_map_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String? businessId;
  Stream<int>? unreadStream;
  Stream<List<Map<String, dynamic>>>? rolesStream;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('business_id');
    if (id == null) return;

    setState(() {
      businessId = id;
      // Created exactly once — not on every build.
      unreadStream = SB.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('business_id', id)
          .map((rows) => rows.where((r) => r['is_read'] == false).length);

      rolesStream = SB.client
          .from('roles')
          .stream(primaryKey: ['id'])
          .eq('business_id', id)
          .order('name');
    });
  }

  Future<void> _addRole() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Role'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Role name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty || businessId == null) return;

    try {
      await SB.client.from('roles').insert({'business_id': businessId, 'name': name.toLowerCase()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add role: $e')));
    }
  }

  Future<void> _deleteRole(String roleId, String roleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete "$roleName"? Existing personnel keep this role label, but it won\'t be selectable for new registrations.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await SB.client.from('roles').delete().eq('id', roleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (businessId == null || rolesStream == null || unreadStream == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen(isAdmin: true))),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Live Map',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveMapScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: 'Invite Codes',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteCodesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.storage_outlined),
            tooltip: 'Data Retention',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataRetentionScreen())),
          ),
          StreamBuilder<int>(
            stream: unreadStream,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addRole, tooltip: 'Add Role', child: const Icon(Icons.add)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: rolesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final roles = snapshot.data!;
          if (roles.isEmpty) {
            return const Center(child: Text('No roles yet. Tap + to add one.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: roles.length,
            itemBuilder: (context, index) {
              final roleRow = roles[index];
              final roleName = roleRow['name'] as String;
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.work, color: Colors.white)),
                  title: Text(roleName.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tap to view personnel'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey), onPressed: () => _deleteRole(roleRow['id'], roleName)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoleUsersScreen(role: roleName))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}