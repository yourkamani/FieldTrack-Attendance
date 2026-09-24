import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/supabase_client.dart';
import '../../core/auth/supabase_email_admin_auth_provider.dart';
import '../auth/login_screen.dart';
import '../admin/admin_login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isAdmin;
  const ProfileScreen({Key? key, required this.isAdmin}) : super(key: key);
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameCtrl = TextEditingController();
  String? recordId;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    recordId = prefs.getString('user_id');
    final table = widget.isAdmin ? 'admins' : 'users';
    final row = await SB.client.from(table).select('name').eq('id', recordId!).maybeSingle();
    nameCtrl.text = row?['name'] ?? '';
    setState(() => loading = false);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final table = widget.isAdmin ? 'admins' : 'users';
    await SB.client.from(table).update({'name': nameCtrl.text.trim()}).eq('id', recordId!);
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    if (widget.isAdmin) {
      await SupabaseEmailAdminAuthProvider().signOut();
      await prefs.clear();
    } else {
      await prefs.remove('user_id');
      await prefs.remove('role');
      // business_id intentionally kept — no invite code needed on next login
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder: (_) => widget.isAdmin ? const AdminLoginScreen() : const LoginScreen()),
      (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), onPressed: saving ? null : _save,
            child: saving ? const CircularProgressIndicator() : const Text('Save')),
          const SizedBox(height: 40),
          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50), foregroundColor: Colors.red), onPressed: _logout, child: const Text('Log Out')),
        ]),
      ),
    );
  }
}