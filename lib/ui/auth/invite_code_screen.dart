import 'package:flutter/material.dart';
import '../../core/invite_service.dart';
import 'register_details_screen.dart';

class InviteCodeScreen extends StatefulWidget {
  final String phone;
  const InviteCodeScreen({Key? key, required this.phone}) : super(key: key);
  @override
  _InviteCodeScreenState createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends State<InviteCodeScreen> {
  final codeCtrl = TextEditingController();
  bool loading = false;

  Future<void> _submit() async {
    setState(() => loading = true);
    final businessId = await InviteService.resolveBusinessId(codeCtrl.text.trim().toUpperCase());

    if (businessId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid or inactive invite code')));
        setState(() => loading = false);
      }
      return;
    }

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => RegisterDetailsScreen(phone: widget.phone, businessId: businessId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Invite Code')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("New phone number — ask your admin for your business invite code.", textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Invite Code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 30),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _submit,
                    child: const Text('CONTINUE'),
                  ),
          ],
        ),
      ),
    );
  }
}