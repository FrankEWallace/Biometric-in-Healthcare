import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_snackbar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final user  = context.watch<AuthProvider>().user;
    final cs    = Theme.of(context).colorScheme;

    if (user == null) {
      // Signing out clears the user before this screen finishes popping.
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile card ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 36,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 14),
                Text(user.name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(user.email,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                _RoleBadge(role: user.role),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Edit Profile ──────────────────────────────────────────────────
          _SectionHeader(label: 'Profile'),
          _SettingsTile(
            icon: Icons.edit_rounded,
            label: 'Edit Profile',
            subtitle: 'Update your display name',
            onTap: () => _showEditProfile(context, user),
          ),

          const SizedBox(height: 16),

          // ── Settings ──────────────────────────────────────────────────────
          _SectionHeader(label: 'Settings'),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              children: [

                // Change password
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        size: 18, color: AppColors.warning),
                  ),
                  title: Text('Change Password',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface)),
                  subtitle: Text('Update your account password',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  onTap: () => _showChangePassword(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Account info ──────────────────────────────────────────────────
          _SectionHeader(label: 'Account'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Username', value: '@${user.username}'),
                Divider(height: 16, color: cs.outline),
                _InfoRow(label: 'Role', value: _roleLabel(user.role)),
                if (user.hospitalId != null) ...[
                  Divider(height: 16, color: cs.outline),
                  _InfoRow(label: 'Hospital ID', value: '${user.hospitalId}'),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Sign out ──────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1.5),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Edit profile sheet ──────────────────────────────────────────────────────

  void _showEditProfile(BuildContext context, dynamic user) {
    final nameCtrl = TextEditingController(text: user.name as String);
    final formKey  = GlobalKey<FormState>();
    bool saving    = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('Edit Profile',
                      style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Name *'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheetState(() => saving = true);

                              final ok = await context
                                  .read<AuthProvider>()
                                  .updateProfile(name: nameCtrl.text.trim());

                              if (!context.mounted) return;
                              Navigator.pop(ctx);

                              if (ok) {
                                showStatusSnackbar(context,
                                    message: 'Profile updated successfully.',
                                    status: SnackStatus.success);
                              } else {
                                final err = context.read<AuthProvider>().errorMessage
                                    ?? 'Update failed.';
                                showStatusSnackbar(context,
                                    message: err,
                                    status: SnackStatus.error);
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Change password sheet ───────────────────────────────────────────────────

  void _showChangePassword(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey     = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Change Password',
                    style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 20),
                TextFormField(
                  controller: currentCtrl,
                  decoration: const InputDecoration(labelText: 'Current Password'),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: newCtrl,
                  decoration: const InputDecoration(labelText: 'New Password'),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: confirmCtrl,
                  decoration: const InputDecoration(labelText: 'Confirm Password'),
                  obscureText: true,
                  validator: (v) =>
                      v != newCtrl.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(ctx);
                        showStatusSnackbar(context,
                            message: 'Password changed successfully.',
                            status: SnackStatus.success);
                      }
                    },
                    child: const Text('Update Password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sign out dialog ─────────────────────────────────────────────────────────

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(90, 42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (!context.mounted) return;
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':       return 'Hospital Admin';
      case 'super_admin': return 'Super Admin';
      case 'doctor':      return 'Doctor';
      default:            return 'Nurse';
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        title: Text(label,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded,
            size: 20, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (role) {
      'admin'       => ('Hospital Admin',  AppColors.primary,     AppColors.primaryTint),
      'super_admin' => ('Super Admin',     AppColors.primaryDark, AppColors.primaryTint),
      'doctor'      => ('Doctor',          AppColors.success,     AppColors.successLight),
      _             => ('Nurse',           AppColors.warning,     AppColors.warningLight),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
