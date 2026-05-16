import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';

class SupervisorOverrideScreen extends StatefulWidget {
  const SupervisorOverrideScreen({super.key});

  @override
  State<SupervisorOverrideScreen> createState() =>
      _SupervisorOverrideScreenState();
}

class _SupervisorOverrideScreenState extends State<SupervisorOverrideScreen> {
  final _service = VisitService();

  List<Map<String, dynamic>> _overrides = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _service.getPendingOverrides(token: _token);
      if (mounted) setState(() { _overrides = list; _loading = false; });
    } on VisitException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _approve(int overrideId) async {
    final confirmed = await _showConfirmDialog(
      title: 'Approve Override',
      message: 'This will bypass biometric verification and mark the stage as completed.',
      confirmLabel: 'Approve',
      confirmColor: AppColors.success,
    );
    if (confirmed != true || !mounted) return;
    await _resolve(overrideId, 'approved', null);
  }

  Future<void> _deny(int overrideId) async {
    final note = await _showNoteDialog(
      title: 'Deny Override',
      hint: 'Reason for denial (optional)',
    );
    if (note == null || !mounted) return;
    await _resolve(overrideId, 'denied', note.trim().isEmpty ? null : note.trim());
  }

  Future<void> _resolve(int overrideId, String decision, String? note) async {
    try {
      await _service.resolveOverride(
        token: _token,
        overrideId: overrideId,
        decision: decision,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Override ${decision == 'approved' ? 'approved' : 'denied'}.'),
          backgroundColor:
              decision == 'approved' ? AppColors.success : AppColors.error,
        ),
      );
      _load();
    } on VisitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showNoteDialog({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Deny', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Override Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _overrides.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded,
                              size: 56,
                              color: cs.onSurfaceVariant.withAlpha(100)),
                          const SizedBox(height: 12),
                          Text('No pending override requests',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 15)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _overrides.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _OverrideTile(
                          data: _overrides[i],
                          onApprove: () => _approve(_overrides[i]['id'] as int),
                          onDeny: () => _deny(_overrides[i]['id'] as int),
                        ),
                      ),
                    ),
    );
  }
}

// ── Override tile ──────────────────────────────────────────────────────────────

class _OverrideTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const _OverrideTile({
    required this.data,
    required this.onApprove,
    required this.onDeny,
  });

  String get _stageName {
    final stage = (data['visit_stage'] as Map<String, dynamic>?)?['stage']
        as String? ?? '';
    return switch (stage) {
      'clerk_checkin'  => 'Check-in',
      'triage'         => 'Triage',
      'consultation'   => 'Consultation',
      'laboratory'     => 'Laboratory',
      'pharmacy'       => 'Pharmacy',
      'clerk_checkout' => 'Checkout',
      _                => stage,
    };
  }

  String get _patientName {
    final visitStage = data['visit_stage'] as Map<String, dynamic>?;
    final visit = visitStage?['visit'] as Map<String, dynamic>?;
    final patient = visit?['patient'] as Map<String, dynamic>?;
    return patient?['full_name'] as String? ?? 'Unknown Patient';
  }

  String get _patientDisplayId {
    final visitStage = data['visit_stage'] as Map<String, dynamic>?;
    final visit = visitStage?['visit'] as Map<String, dynamic>?;
    final patient = visit?['patient'] as Map<String, dynamic>?;
    return patient?['hospital_patient_id'] as String?
        ?? '#${patient?['id'] ?? ''}';
  }

  String get _requestedBy {
    final staff = data['requested_by_user'] as Map<String, dynamic>?;
    return staff?['name'] as String? ?? 'Unknown staff';
  }

  String get _fallbackChain {
    return data['fallback_chain'] as String? ?? '';
  }

  String? get _staffNote => data['staff_note'] as String?;

  String _elapsed() {
    final raw = data['requested_at'] as String?;
    if (raw == null) return '';
    try {
      final dt  = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _stageName,
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.access_time_rounded, size: 12,
                  color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(_elapsed(),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),

          // Patient
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_patientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(_patientDisplayId,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
            ],
          ),

          const Divider(height: 20),

          // Staff info
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Requested by',
            value: _requestedBy,
          ),
          const SizedBox(height: 4),
          _InfoRow(
            icon: Icons.alt_route_rounded,
            label: 'Fallback tried',
            value: _fallbackChain,
          ),
          if (_staffNote != null && _staffNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _staffNote!,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Deny'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
