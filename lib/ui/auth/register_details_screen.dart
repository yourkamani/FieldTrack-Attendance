import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgrest/postgrest.dart';
import '../../core/supabase_client.dart';
import '../user/tracker_screen.dart';

class RegisterDetailsScreen extends StatefulWidget {
  final String phone;
  final String businessId;
  const RegisterDetailsScreen({Key? key, required this.phone, required this.businessId}) : super(key: key);
  @override
  _RegisterDetailsScreenState createState() => _RegisterDetailsScreenState();
}

class _RegisterDetailsScreenState extends State<RegisterDetailsScreen> {
  final nameCtrl = TextEditingController();
  String role = 'driver';
  bool loading = false;
  final roles = ['driver', 'master', 'blaster', 'operator'];

  Future<void> _register() async {
    if (nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your name')));
      return;
    }
    setState(() => loading = true);

    try {
      final res = await SB.client.from('users').insert({
        'phone': widget.phone,
        'name': nameCtrl.text,
        'role': role,
        'business_id': widget.businessId,
      }).select().single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', res['id']);
      await prefs.setString('business_id', widget.businessId);
      await prefs.setString('role', res['role']);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackerScreen()));
      }
    } on PostgrestException catch (e) {
      final msg = e.message.contains('User limit reached')
          ? 'This business has reached its user limit. Contact your admin.'
          : 'Error: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Registration')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Select Role', border: OutlineInputBorder()),
              items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
              onChanged: (val) => setState(() => role = val!),
            ),
            const SizedBox(height: 30),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _register,
                    child: const Text('REGISTER'),
                  ),
          ],
        ),
      ),
    );
  }
}