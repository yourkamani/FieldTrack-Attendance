import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/invite_service.dart';
import '../../core/supabase_client.dart';

class InviteCodesScreen extends StatefulWidget {
  const InviteCodesScreen({Key? key}) : super(key: key);
  @override
  State<InviteCodesScreen> createState() => _InviteCodesScreenState();
}

class _InviteCodesScreenState extends State<InviteCodesScreen> {
  String? businessId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() => businessId = p.getString('business_id')));
  }

  Future<void> _generate() async {
    if (businessId == null) return;
    final code = await InviteService.generateCode(businessId!);
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('New Invite Code'),
          content: SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (businessId == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final stream = SB.client
        .from('invite_codes')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId!)
        .order('created_at', ascending: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Invite Codes')),
      floatingActionButton: FloatingActionButton(onPressed: _generate, child: const Icon(Icons.add)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        final newCode = await InviteService.resetCode(c['id']);
                        if (context.mounted) {
                          showDialog(context: context, builder: (_) => AlertDialog(
                            title: const Text('Code Reset'),
                            content: SelectableText(newCode, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ));
                        }
                      },
                    ),
                    Switch(value: c['is_active'] == true, onChanged: (val) async { /* unchanged */ }),
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