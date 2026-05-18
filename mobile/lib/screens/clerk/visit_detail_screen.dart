import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/visit.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../camera_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  final int visitId;
  const VisitDetailScreen({super.key, required this.visitId});

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  final _visitService = VisitService();
  final _fpService    = FingerprintService();

  VisitModel? _visit;
  bool _loading = true;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().user?.token ?? '';
    setState(() { _loading = true; _error = null; });
    try {
      final visit = await _visitService.getVisit(token: token, visitId: widget.visitId);
      if (mounted) setState(() { _visit = visit; _loading = false; });
    } on VisitException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _startCheckout() async {
    final token = context.read<AuthProvider>().user?.token ?? '';

    // Step 1: capture fingerprint
    final XFile? image = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          title: 'Checkout — Scan Fingerprint',
          showFingerprintOverlay: true,
          returnImageOnly: true,
          isHandCapture: true,
        ),
      ),
    );
    if (image == null || !mounted) return;

    setState(() { _closing = true; _error = null; });

    try {
      final fpResult = await _fpService.verifyFingerprint(
        File(image.path),
        token: token,
        patientId: _visit!.patientId.toString(),
      );

      if (!fpResult.isMatch) {
        setState(() {
          _closing = false;
          _error = 'Fingerprint did not match. Cannot close visit.';
        });
        return;
      }

      await _visitService.closeVisit(
        token: token,
        visitId: widget.visitId,
        verificationLogId: fpResult.verificationLogId!,
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Visit closed successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
      navigator.pop();
    } on VisitException catch (e) {
      if (mounted) setState(() { _closing = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _closing = false; _error = 'Unexpected error.'; });
    }
  }

  Future<void> _reopen() async {
    final reason = await _showReopenDialog();
    if (reason == null || reason.trim().isEmpty) return;
    if (!mounted) return;

    final token = context.read<AuthProvider>().user?.token ?? '';
    try {
      final updated = await _visitService.reopenVisit(
        token: token,
        visitId: widget.visitId,
        reason: reason,
      );
      if (mounted) setState(() => _visit = updated);
    } on VisitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<String?> _showReopenDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Visit'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason for reopening',
            hintText: 'e.g. Patient returned — wrong medication',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final user = context.read<AuthProvider>().user!;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Visit Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _visit == null
              ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
              : _VisitDetailBody(
                  visit: _visit!,
                  isClerk: user.isClerk,
                  closing: _closing,
                  error: _error,
                  onCheckout: _startCheckout,
                  onReopen: _reopen,
                ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _VisitDetailBody extends StatelessWidget {
  final VisitModel visit;
  final bool isClerk;
  final bool closing;
  final String? error;
  final VoidCallback onCheckout;
  final VoidCallback onReopen;

  const _VisitDetailBody({
    required this.visit,
    required this.isClerk,
    required this.closing,
    required this.error,
    required this.onCheckout,
    required this.onReopen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient header
          _PatientHeader(visit: visit),
          const SizedBox(height: 16),

          // Stage timeline
          Text('Stage Timeline',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _StageTimeline(stages: visit.stages),

          // Error
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action buttons (clerk only)
          if (isClerk) ...[
            if (visit.isOpen)
              PrimaryButton(
                label: closing ? 'Closing Visit…' : 'Checkout & Close Visit',
                onPressed: closing ? null : onCheckout,
                isLoading: closing,
              ),
            if (visit.isClosed) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Visit closed at ${_formatTime(visit.closedAt ?? '')}',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onReopen,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reopen Visit'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ── Patient header card ───────────────────────────────────────────────────────

class _PatientHeader extends StatelessWidget {
  final VisitModel visit;
  const _PatientHeader({required this.visit});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final patient = visit.patient;

    final (statusColor, statusBg, statusLabel) = visit.isOpen
        ? (AppColors.success, AppColors.successLight, 'Open')
        : (AppColors.textSecondary, const Color(0xFFE2E8F0), 'Closed');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient?.fullName ?? 'Patient #${visit.patientId}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(patient?.displayId ?? '',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _InfoChip(
                label: 'Type',
                value: visit.visitTypeLabel,
                icon: Icons.local_hospital_rounded,
              ),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'Opened',
                value: _formatTime(visit.openedAt),
                icon: Icons.schedule_rounded,
              ),
              if (visit.reopenCount > 0) ...[
                const SizedBox(width: 12),
                _InfoChip(
                  label: 'Reopens',
                  value: '${visit.reopenCount}×',
                  icon: Icons.refresh_rounded,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoChip({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('$label: ',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Stage timeline ────────────────────────────────────────────────────────────

class _StageTimeline extends StatelessWidget {
  final List<VisitStageModel> stages;
  const _StageTimeline({required this.stages});

  static const _stageOrder = [
    'clerk_checkin',
    'triage',
    'consultation',
    'laboratory',
    'pharmacy',
    'clerk_checkout',
  ];

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final stageMap = {for (final s in stages) s.stage: s};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: _stageOrder.asMap().entries.map((entry) {
          final i     = entry.key;
          final name  = entry.value;
          final stage = stageMap[name];
          final isLast = i == _stageOrder.length - 1;

          return _StageTile(
            stage: stage,
            stageName: name,
            isLast: isLast,
          );
        }).toList(),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  final VisitStageModel? stage;
  final String stageName;
  final bool isLast;

  const _StageTile({
    required this.stage,
    required this.stageName,
    required this.isLast,
  });

  String get _label => switch (stageName) {
    'clerk_checkin'  => 'Check-in',
    'triage'         => 'Triage',
    'consultation'   => 'Consultation',
    'laboratory'     => 'Laboratory',
    'pharmacy'       => 'Pharmacy',
    'clerk_checkout' => 'Checkout',
    _                => stageName,
  };

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final completed = stage?.isCompleted ?? false;
    final time      = stage?.verifiedAt;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: completed ? AppColors.success : cs.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    completed ? Icons.check_rounded : Icons.radio_button_unchecked_rounded,
                    size: 14,
                    color: completed ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: completed
                          ? AppColors.success.withAlpha(80)
                          : cs.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Stage label + time
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_label,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: completed ? cs.onSurface : cs.onSurfaceVariant,
                          fontSize: 14)),
                  if (time != null)
                    Text(_formatTime(time),
                        style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w500))
                  else
                    Text('Pending',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
