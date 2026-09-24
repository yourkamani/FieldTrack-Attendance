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

class _InviteCodesScreenState extends State<InviteCodesScreen> {
  String? businessId;
  Stream<List<Map<String, dynamic>>>? codesStream;

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
      codesStream = SB.client
          .from('invite_codes')
          .stream(primaryKey: ['id'])
          .eq('business_id', id)
          .order('created_at', ascending: false);
    });
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _generate() async {
    if (businessId == null) return;
    final code = await InviteService.generateCode(businessId!);
    if (mounted) _showCodeDialog('New Invite Code', code);
  }

  void _showCodeDialog(String title, String code) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(code)),
          ],
        ),
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
      appBar: AppBar(title: const Text('Invite Codes')),
      floatingActionButton: FloatingActionButton(onPressed: _generate, child: const Icon(Icons.add)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: () => _copy(c['code'])),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reset',
                      onPressed: () async {
                        final newCode = await InviteService.resetCode(c['id']);
                        if (mounted) _showCodeDialog('Code Reset', newCode);
                      },
                    ),
                    Switch(
                      value: c['is_active'] == true,
                      onChanged: (val) async {
                        await SB.client.from('invite_codes').update({'is_active': val}).eq('id', c['id']);
                      },
                    ),
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