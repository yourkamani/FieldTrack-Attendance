import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import '../../core/admin_service.dart';
import 'user_tracks_screen.dart';
import 'live_map_screen.dart';
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
  List<dynamic> allUsers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('business_id');
    if (id == null) return;

    final result = await SB.client
        .from('users')
        .select()
        .eq('role', widget.role)
        .eq('business_id', id)
        .order('name');

    setState(() {
      businessId = id;
      allUsers = result;
      loading = false;
    });
  }

  // Called after edit/delete to refresh the cached list without
  // dropping back into a full-screen spinner.
  Future<void> _refresh() async {
    if (businessId == null) return;
    final result = await SB.client
        .from('users')
        .select()
        .eq('role', widget.role)
        .eq('business_id', businessId!)
        .order('name');
    setState(() => allUsers = result);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final users = allUsers.where((u) =>
      u['name'].toString().toLowerCase().contains(searchQuery) ||
      u['phone'].toString().contains(searchQuery)).toList();

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
            child: users.isEmpty
                ? const Center(child: Text('No personnel found for this role.'))
                : ListView.builder(
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
                              tooltip: 'Live location',
                              onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => LiveMapScreen(focusUserId: user['id']))),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  final changed = await showDialog<bool>(context: context,
                                    builder: (_) => EditUserDialog(userId: user['id'], currentName: user['name'], currentRole: user['role']));
                                  if (changed == true) _refresh();
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
                                    _refresh();
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
                  ),
          ),
        ],
      ),
    );
  }
}