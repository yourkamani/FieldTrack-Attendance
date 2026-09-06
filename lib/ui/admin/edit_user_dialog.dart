import 'package:flutter/material.dart';
import '../../core/admin_service.dart';

class EditUserDialog extends StatefulWidget {
  final String userId;
  final String currentName;
  final String currentRole;
  const EditUserDialog({
    Key? key,
    required this.userId,
    required this.currentName,
    required this.currentRole,
  }) : super(key: key);

  @override
  State<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<EditUserDialog> {
  late final TextEditingController nameCtrl;
  late String role;
  bool saving = false;

  final roles = ['driver', 'master', 'blaster', 'operator'];

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.currentName);
    role = widget.currentRole;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await AdminService.updateUser(userId: widget.userId, name: nameCtrl.text, role: role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Personnel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
            onChanged: (val) => setState(() => role = val!),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: saving ? null : _save,
          child: saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}