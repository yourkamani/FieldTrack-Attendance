import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/invite_service.dart';
import '../../core/supabase_client.dart';

class InviteCodesScreen extends StatefulWidget {
  const InviteCodesScreen({Key? key}) : super(key: key);
  @override
  State<InviteCodesScreen> createState() => _InviteCodesScreenState();
}

class _InviteCodesScreenState extends State<InviteCodesScreen> with SingleTickerProviderStateMixin {
  String? businessId;
  String? myAdminId;
  Stream<List<Map<String, dynamic>>>? codesStream;
  Stream<List<Map<String, dynamic>>>? adminInvitesStream;
  Stream<List<Map<String, dynamic>>>? adminsStream;
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('business_id');
    if (id == null) return;
    setState(() {
      businessId = id;
      myAdminId = prefs.getString('user_id');
      codesStream = SB.client
          .from('invite_codes')
          .stream(primaryKey: ['id'])
          .eq('business_id', id)
          .order('created_at', ascending: false);
      adminInvitesStream = SB.client
          .from('admin_invites')
          .stream(primaryKey: ['id'])
          .eq('business_id', id)
          .order('created_at', ascending: false);
      adminsStream = SB.client.from('admins').stream(primaryKey: ['id']).eq('business_id', id);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _toast('Copied to clipboard');
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _generate() async {
    try {
      if (_tabs.index == 0) {
        if (businessId == null) return;
        final code = await InviteService.generateCode(businessId!);
        if (mounted) _showCodeDialog('New Employee Code', code);
      } else {
        final code = await InviteService.createAdminInvite();
        if (mounted) _showCodeDialog('New Admin Invite', code, note: 'Single use. Expires in 7 days.');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  void _showCodeDialog(String title, String code, {String? note}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(code)),
          ]),
          if (note != null) Text(note, style: const TextStyle(color: Colors.grey)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (businessId == null || codesStream == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Codes'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Employees'), Tab(text: 'Admins')]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _generate,
        tooltip: _tabs.index == 0 ? 'New employee code' : 'New admin invite',
        child: const Icon(Icons.add),
      ),
      body: TabBarView(controller: _tabs, children: [_employeeTab(), _adminTab()]),
    );
  }

  // ---------------- Employees tab ----------------
  Widget _employeeTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: codesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final codes = snapshot.data!;
        if (codes.isEmpty) return const Center(child: Text('No invite codes yet. Tap + to create one.'));

        return ListView.builder(
          itemCount: codes.length,
          itemBuilder: (context, index) {
            final c = codes[index];
            return ListTile(
              title: Text(c['code'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text(c['is_active'] == true ? 'Active' : 'Deactivated'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: () => _copy(c['code'])),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset',
                  onPressed: () async {
                    final newCode = await InviteService.resetCode(c['id']);
                    if (mounted) _showCodeDialog('Code Reset', newCode);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete',
                  onPressed: () async {
                    if (!await _confirm('Delete code', 'Delete ${c['code']}? Employees already registered keep their accounts, but nobody can join with this code again.')) return;
                    try {
                      await InviteService.deleteCode(c['id']);
                    } catch (e) {
                      _toast('$e');
                    }
                  },
                ),
                Switch(
                  value: c['is_active'] == true,
                  onChanged: (val) async {
                    await SB.client.from('invite_codes').update({'is_active': val}).eq('id', c['id']);
                  },
                ),
              ]),
            );
          },
        );
      },
    );
  }

  // ---------------- Admins tab ----------------
  Widget _adminTab() {
    return ListView(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Admins in this business', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: adminsStream,
        builder: (context, snap) {
          final admins = snap.data ?? [];
          return Column(children: [
            for (final a in admins)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings)),
                title: Text((a['name'] ?? a['email'] ?? 'Admin').toString()),
                subtitle: a['id'] == myAdminId ? const Text('You') : null,
                trailing: a['id'] == myAdminId
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                        tooltip: 'Remove admin',
                        onPressed: () async {
                          if (!await _confirm('Remove admin', 'Remove ${a['name'] ?? 'this admin'} from the business? They lose access immediately.')) return;
                          try {
                            await InviteService.removeAdmin(a['id']);
                          } catch (e) {
                            _toast('$e');
                          }
                        },
                      ),
              ),
          ]);
        },
      ),
      const Divider(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('Admin invite codes', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: adminInvitesStream,
        builder: (context, snap) {
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          final invites = snap.data!;
          if (invites.isEmpty) {
            return const Padding(padding: EdgeInsets.all(16), child: Text('No admin invites. Tap + to create a single-use code.'));
          }
          return Column(children: [
            for (final i in invites)
              Builder(builder: (_) {
                final used = i['used_at'] != null;
                final expired = !used && DateTime.parse(i['expires_at']).isBefore(DateTime.now());
                final status = used ? 'Used' : (expired ? 'Expired' : 'Active');
                return ListTile(
                  title: Text(i['code'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: status == 'Active' ? null : Colors.grey)),
                  subtitle: Text(status),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (status == 'Active') IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(i['code'])),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete',
                      onPressed: () async {
                        if (!await _confirm('Delete invite', 'Delete admin invite ${i['code']}?')) return;
                        try {
                          await InviteService.deleteAdminInvite(i['id']);
                        } catch (e) {
                          _toast('$e');
                        }
                      },
                    ),
                  ]),
                );
              }),
          ]);
        },
      ),
    ]);
  }
}
