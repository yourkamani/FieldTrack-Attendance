import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_tracks_screen.dart';

class RoleUsersScreen extends StatefulWidget {
  final String role;
  const RoleUsersScreen({Key? key, required this.role}) : super(key: key);

  @override
  _RoleUsersScreenState createState() => _RoleUsersScreenState();
}

class _RoleUsersScreenState extends State<RoleUsersScreen> {
  final _supabase = Supabase.instance.client;
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.role.toUpperCase()} Personnel')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search by name or phone', 
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
              ),
              onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _supabase.from('users').select().eq('role', widget.role).order('name', ascending: true),
              builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                var users = snapshot.data!.where((u) => 
                  u['name'].toString().toLowerCase().contains(searchQuery) ||
                  u['phone'].toString().contains(searchQuery)
                ).toList();

                if (users.isEmpty) {
                  return const Center(child: Text('No personnel found for this role.', style: TextStyle(fontSize: 16)));
                }

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
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => UserTracksScreen(userId: user['id'], userName: user['name'])
                        )),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}