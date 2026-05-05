import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/staff_service.dart';
import '../../widgets/status_snackbar.dart';

class StaffFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(Map<String, dynamic>) onSaved;

  const StaffFormSheet({super.key, this.existing, required this.onSaved});

  @override
  State<StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<StaffFormSheet> {
  final _service = StaffService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _name;
  late TextEditingController _username;
  late TextEditingController _email;
  late TextEditingController _phone;
  late TextEditingController _password;

  String _role = 'nurse';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static const _roleOptions = [
    ('nurse',  'Nurse'),
    ('doctor', 'Doctor'),
    ('admin',  'Admin'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name     = TextEditingController(text: e?['name']     as String? ?? '');
    _username = TextEditingController(text: e?['username'] as String? ?? '');
    _email    = TextEditingController(text: e?['email']    as String? ?? '');
    _phone    = TextEditingController(text: e?['phone']    as String? ?? '');
    _password = TextEditingController();
    _role     = e?['role'] as String? ?? 'nurse';
    if (!_roleOptions.any((r) => r.$1 == _role)) _role = 'nurse';
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _token => context.read<AuthProvider>().user!.token;
  int?  get _hospitalId => context.read<AuthProvider>().user!.hospitalId;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      Map<String, dynamic> result;
      if (_isEdit) {
        await _service.updateStaff(
          token:  _token,
          userId: widget.existing!['id'] as int,
          name:   _name.text.trim(),
          email:  _email.text.trim(),
          role:   _role,
          phone:  _phone.text.trim(),
        );
        result = {...widget.existing!, 'name': _name.text.trim(), 'role': _role};
      } else {
        result = await _service.createStaff(
          token:      _token,
          hospitalId: _hospitalId ?? 1,
          name:       _name.text.trim(),
          username:   _username.text.trim(),
          email:      _email.text.trim(),
          password:   _password.text,
          role:       _role,
        );
      }
      if (mounted) widget.onSaved(result);
    } on StaffException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showStatusSnackbar(context, message: e.message, status: SnackStatus.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showStatusSnackbar(context,
            message: 'An unexpected error occurred.',
            status: SnackStatus.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: cs.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  _isEdit ? 'Edit Staff Member' : 'Add Staff Member',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update name, email, role or phone.'
                      : 'Fill in the details to create a new staff account.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // Full Name
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                ),
                const SizedBox(height: 14),

                // Username (create only)
                if (!_isEdit) ...[
                  TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username *',
                      prefixText: '@',
                    ),
                    autocorrect: false,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Username is required';
                      if (v.trim().length < 3) return 'At least 3 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                // Email
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email *'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Phone (optional)
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    hintText: '+387...',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                // Role dropdown
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role *'),
                  items: _roleOptions
                      .map((r) => DropdownMenuItem(value: r.$1, child: Text(r.$2)))
                      .toList(),
                  onChanged: (v) { if (v != null) setState(() => _role = v); },
                ),
                const SizedBox(height: 14),

                // Password (create only)
                if (!_isEdit) ...[
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password *'),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 8) return 'At least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                const SizedBox(height: 8),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEdit ? 'Save Changes' : 'Create Staff'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
