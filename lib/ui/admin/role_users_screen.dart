import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import '../../core/admin_service.dart';
import 'user_tracks_screen.dart';
import 'live_location_sheet.dart';
import 'edit_user_dialog.dart';

class RoleUsersScreen extends StatefulWidget {
  final String role;
  const RoleUsersScreen({Key? key, required this.role}) : super(key: key);
  @override
  _RoleUsersScreenState createState() => _RoleUsersScreenState();
}

class _RoleUsersScreenState extends State<RoleUsersScreen> {
  String searchQuery = '';
  String? businessId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() => businessId = p.getString('business_id')));
  }

  @override
  Widget build(BuildContext context) {
    if (businessId == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text('${widget.role.toUpperCase()} Personnel')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              decoration: InputDecoration(labelText: 'Search by name or phone', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: SB.client.from('users').select().eq('role', widget.role).eq('business_id', businessId!).order('name'),
              builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var users = snapshot.data!.where((u) =>
                  u['name'].toString().toLowerCase().contains(searchQuery) ||
                  u['phone'].toString().contains(searchQuery)).toList();
                if (users.isEmpty) return const Center(child: Text('No personnel found for this role.'));

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(user['phone']),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.my_location, color: Colors.blue),
                            onPressed: () => showModalBottomSheet(context: context,
                              builder: (_) => LiveLocationSheet(userId: user['id'], userName: user['name'])),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                final changed = await showDialog<bool>(context: context,
                                  builder: (_) => EditUserDialog(userId: user['id'], currentName: user['name'], currentRole: user['role']));
                                if (changed == true) setState(() {});
                              }
                              if (value == 'delete') {
                                final confirmed = await showDialog<bool>(context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Delete Personnel'),
                                    content: Text('This will permanently delete ${user['name']} and all their data. This cannot be undone.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                    ],
                                  ));
                                if (confirmed == true) {
                                  await AdminService.deleteUserCascade(user['id']);
                                  setState(() {});
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ]),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserTracksScreen(userId: user['id'], userName: user['name']))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}