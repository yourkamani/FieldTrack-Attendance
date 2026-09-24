import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import '../../core/data_retention_service.dart';

class DataRetentionScreen extends StatefulWidget {
  const DataRetentionScreen({Key? key}) : super(key: key);
  @override
  State<DataRetentionScreen> createState() => _DataRetentionScreenState();
}

class _DataRetentionScreenState extends State<DataRetentionScreen> {
  String? businessId;
  int? retentionDays;
  bool loading = true;
  bool deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('business_id');
    if (id == null) return;
    final biz = await SB.client.from('businesses').select('data_retention_days').eq('id', id).single();
    setState(() {
      businessId = id;
      retentionDays = biz['data_retention_days'];
      loading = false;
    });
  }

  Future<void> _saveRetention(int days) async {
    if (businessId == null) return;
    await SB.client.from('businesses').update({'data_retention_days': days}).eq('id', businessId!);
    setState(() => retentionDays = days);
  }

  Future<void> _manualDelete() async {
    final cutoff = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (cutoff == null || businessId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('This will permanently delete all location tracks, completed sessions (with selfies), and notifications from before ${cutoff.toLocal().toString().split(' ').first}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => deleting = true);
    try {
      await DataRetentionService.deleteDataBefore(cutoff, businessId!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Old data deleted.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => deleting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Data Retention')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auto-delete after', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: retentionDays,
              items: const [7, 14, 30, 60, 90].map((d) => DropdownMenuItem(value: d, child: Text('$d days'))).toList(),
              onChanged: (val) {
                if (val != null) _saveRetention(val);
              },
            ),
            const Text('Data older than this is deleted automatically every night.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 40),
            const Text('Manual deletion', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Pick a cutoff date — everything before it is deleted immediately.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: deleting ? null : _manualDelete,
              icon: deleting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
              label: const Text('Choose date & delete'),
            ),
          ],
        ),
      ),
    );
  }
}