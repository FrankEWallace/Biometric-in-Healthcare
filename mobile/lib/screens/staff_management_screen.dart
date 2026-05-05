import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/staff_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final _service = StaffService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _staff = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _service.getStaff(token: _token);
      setState(() { _staff = list; _loading = false; });
    } on StaffException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _toggle(Map<String, dynamic> member) async {
    final id       = member['id'] as int;
    final activate = !(member['is_active'] as bool);
    final name     = member['name'] as String;
    final confirm  = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(activate ? 'Reactivate Staff' : 'Deactivate Staff'),
        content: Text(
          activate
              ? 'Reactivate $name? They will regain system access.'
              : 'Deactivate $name? They will immediately lose access.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? AppColors.success : AppColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.setActive(token: _token, userId: id, isActive: activate);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(activate ? '$name reactivated.' : '$name deactivated.'),
          backgroundColor: activate ? AppColors.success : AppColors.error,
        ));
      }
    } on StaffException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateStaffSheet(
        onCreated: () {
          _load();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Staff account created.'),
              backgroundColor: AppColors.success,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            tooltip: 'Add Staff',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_staff.isEmpty) {
      return const Center(
        child: Text('No staff found.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _staff.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _StaffCard(
          member: _staff[i],
          onToggle: () => _toggle(_staff[i]),
        ),
      ),
    );
  }
}

// ── Staff card ────────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onToggle;

  const _StaffCard({required this.member, required this.onToggle});

  static const _roleColors = {
    'super_admin': Color(0xFFDC2626),
    'admin':       Color(0xFFD97706),
    'doctor':      Color(0xFF0284C7),
    'nurse':       Color(0xFF059669),
  };

  static const _roleLabels = {
    'super_admin': 'Super Admin',
    'admin':       'Admin',
    'doctor':      'Doctor',
    'nurse':       'Nurse',
  };

  @override
  Widget build(BuildContext context) {
    final role     = member['role'] as String? ?? 'nurse';
    final isActive = member['is_active'] as bool? ?? false;
    final color    = _roleColors[role] ?? AppColors.textSecondary;
    final isSelf   = member['id'] == context.read<AuthProvider>().user?.id;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              (member['name'] as String? ?? '?')[0].toUpperCase(),
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Info
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              member['name'] as String? ?? '—',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              '@${member['username'] as String? ?? ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _roleLabels[role] ?? role,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.successLight
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ),
            ]),
          ]),
        ),
        // Action
        if (!isSelf)
          IconButton(
            icon: Icon(
              isActive
                  ? Icons.person_off_rounded
                  : Icons.person_rounded,
              size: 20,
              color: isActive ? AppColors.error : AppColors.success,
            ),
            tooltip: isActive ? 'Deactivate' : 'Reactivate',
            onPressed: onToggle,
          ),
      ]),
    );
  }
}

// ── Create staff bottom sheet ─────────────────────────────────────────────────

class _CreateStaffSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateStaffSheet({required this.onCreated});

  @override
  State<_CreateStaffSheet> createState() => _CreateStaffSheetState();
}

class _CreateStaffSheetState extends State<_CreateStaffSheet> {
  final _service    = StaffService();
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _userCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();

  String _role      = 'nurse';
  bool   _loading   = false;
  String? _error;
  bool _showPass    = false;

  static const _roles = [
    ('nurse',  'Nurse'),
    ('doctor', 'Doctor'),
    ('admin',  'Admin'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final authUser = context.read<AuthProvider>().user!;
    try {
      await _service.createStaff(
        token:      authUser.token,
        hospitalId: authUser.hospitalId ?? 0,
        name:       _nameCtrl.text.trim(),
        username:   _userCtrl.text.trim(),
        email:      _emailCtrl.text.trim(),
        password:   _passCtrl.text,
        role:       _role,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
      }
    } on StaffException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add Staff Account',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  CustomTextField(
                    controller: _nameCtrl,
                    label: 'Full Name',
                    hint: 'e.g. Dr. Jane Doe',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    controller: _userCtrl,
                    label: 'Username',
                    hint: 'e.g. jane.doe',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 3) return 'At least 3 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    controller: _emailCtrl,
                    label: 'Email',
                    hint: 'e.g. jane.doe@hospital.ba',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: !_showPass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Min 8 characters',
                      suffixIcon: IconButton(
                        icon: Icon(_showPass
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 8) return 'At least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  // Role selector
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Role',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _role,
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        borderRadius: BorderRadius.circular(12),
                        items: _roles
                            .map((r) => DropdownMenuItem(
                                  value: r.$1,
                                  child: Text(r.$2),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _role = v);
                        },
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Create Account',
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
