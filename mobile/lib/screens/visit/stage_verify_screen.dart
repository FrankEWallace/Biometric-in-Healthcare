import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/visit.dart';
import '../../providers/auth_provider.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../camera_screen.dart';

enum _VerifyPhase { fingerprint, face, override }

/// Reusable stage verification screen.
/// Used by nurse (triage), doctor (consultation), lab tech, pharmacist.
class StageVerifyScreen extends StatefulWidget {
  final VisitModel visit;
  final String stageName;

  const StageVerifyScreen({
    super.key,
    required this.visit,
    required this.stageName,
  });

  @override
  State<StageVerifyScreen> createState() => _StageVerifyScreenState();
}

class _StageVerifyScreenState extends State<StageVerifyScreen> {
  final _visitService = VisitService();

  XFile? _capturedImage;
  bool _verifying = false;
  bool _verified = false;
  Map<String, dynamic>? _simulatedData;
  String? _error;
  int _fpAttempts = 0;
  _VerifyPhase _phase = _VerifyPhase.fingerprint;
  static const int _maxAttempts = 3;

  String get _stageLabel => switch (widget.stageName) {
    'triage'         => 'Triage',
    'consultation'   => 'Consultation',
    'laboratory'     => 'Laboratory',
    'pharmacy'       => 'Pharmacy',
    _                => widget.stageName,
  };

  Future<void> _openCamera() async {
    setState(() => _error = null);
    final bool isFace = _phase == _VerifyPhase.face;
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          title: isFace ? 'Face Scan — $_stageLabel' : 'Scan — $_stageLabel',
          showFingerprintOverlay: !isFace,
          returnImageOnly: true,
          isHandCapture: !isFace,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _capturedImage = result);
  }

  Future<void> _verify() async {
    if (_capturedImage == null) return;

    final token = context.read<AuthProvider>().user?.token ?? '';
    final isFace = _phase == _VerifyPhase.face;
    setState(() { _verifying = true; _error = null; });
    if (!isFace) _fpAttempts++;

    try {
      final bytes       = await File(_capturedImage!.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      final result = await _visitService.verifyStage(
        token:            token,
        visitId:          widget.visit.id,
        stage:            widget.stageName,
        fingerprintImage: isFace ? '' : base64Image,
        faceImage:        isFace ? base64Image : null,
      );

      if (!mounted) return;

      setState(() {
        _verifying     = false;
        _verified      = true;
        _simulatedData = result['simulated_data'] as Map<String, dynamic>?;
      });
    } on VisitException catch (e) {
      if (!mounted) return;

      if (e.message.contains('already been verified')) {
        setState(() { _verifying = false; _error = e.message; });
        return;
      }

      // After fingerprint exhaustion → switch to face fallback
      if (!isFace && _fpAttempts >= _maxAttempts) {
        setState(() {
          _verifying     = false;
          _capturedImage = null;
          _phase         = _VerifyPhase.face;
          _error         = 'Fingerprint failed $_fpAttempts times. Try face scan.';
        });
        return;
      }

      // Face failed → offer override
      if (isFace) {
        setState(() {
          _verifying     = false;
          _capturedImage = null;
          _phase         = _VerifyPhase.override;
          _error         = 'Face scan did not match. Request a supervisor override.';
        });
        return;
      }

      setState(() {
        _verifying     = false;
        _capturedImage = null;
        _error = 'Fingerprint did not match. ${_maxAttempts - _fpAttempts} attempt(s) remaining.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifying     = false;
          _capturedImage = null;
          _error         = 'Unexpected error. Please try again.';
        });
      }
    }
  }

  Future<void> _requestOverride() async {
    final stage = widget.visit.stageByName(widget.stageName);
    if (stage == null) return;

    final token = context.read<AuthProvider>().user?.token ?? '';
    try {
      await _visitService.requestOverride(
        token: token,
        visitStageId: stage.id,
        fallbackChain: 'fingerprint_and_face_failed',
        staffNote: 'Fingerprint failed $_fpAttempts time(s), face scan also failed.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Override request sent to supervisor.'),
          backgroundColor: AppColors.warning,
        ),
      );
    } on VisitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: Text(_stageLabel)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient card
              _PatientCard(visit: widget.visit),
              const SizedBox(height: 24),

              if (!_verified) ...[
                // Phase banner
                if (_phase == _VerifyPhase.face) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.face_retouching_natural,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Fingerprint failed. Please scan your face instead.',
                            style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Scan section
                Text(
                  _phase == _VerifyPhase.face
                      ? 'Face Verification'
                      : 'Verify Patient Identity',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  _phase == _VerifyPhase.face
                      ? 'Position the patient\'s face in the frame to verify identity.'
                      : 'Scan the patient\'s fingerprint to access the $_stageLabel record.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 20),

                // Capture area
                if (_phase != _VerifyPhase.override)
                  GestureDetector(
                    onTap: _verifying ? null : _openCamera,
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        color: _capturedImage != null
                            ? AppColors.successLight
                            : cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _capturedImage != null
                              ? AppColors.success
                              : cs.outline,
                          width: _capturedImage != null ? 2 : 1,
                        ),
                      ),
                      child: _capturedImage != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.success, size: 40),
                                const SizedBox(height: 8),
                                const Text('Image ready',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('Tap to recapture',
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12)),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _phase == _VerifyPhase.face
                                      ? Icons.face_rounded
                                      : Icons.fingerprint,
                                  size: 44,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _phase == _VerifyPhase.face
                                      ? 'Tap to scan face'
                                      : 'Tap to scan fingerprint',
                                  style:
                                      TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                    ),
                  ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _phase == _VerifyPhase.override
                          ? AppColors.warningLight
                          : AppColors.errorLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _phase == _VerifyPhase.override
                              ? Icons.warning_amber_rounded
                              : Icons.error_outline_rounded,
                          color: _phase == _VerifyPhase.override
                              ? AppColors.warning
                              : AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  color: _phase == _VerifyPhase.override
                                      ? AppColors.warning
                                      : AppColors.error,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                if (_phase != _VerifyPhase.override)
                  PrimaryButton(
                    label: _verifying
                        ? 'Verifying…'
                        : _phase == _VerifyPhase.face
                            ? 'Verify Face'
                            : 'Verify Fingerprint',
                    onPressed:
                        _capturedImage != null && !_verifying ? _verify : null,
                    isLoading: _verifying,
                  ),

                // Fingerprint attempt counter
                if (_phase == _VerifyPhase.fingerprint && _fpAttempts > 0) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Attempt $_fpAttempts of $_maxAttempts',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ],

                // Override button — shown when all biometrics exhausted
                if (_phase == _VerifyPhase.override) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _requestOverride,
                      icon: const Icon(Icons.supervisor_account_rounded),
                      label: const Text('Request Supervisor Override'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ] else ...[
                // ── Verified — show simulated data ──────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Patient verified — $_stageLabel record unlocked.',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_simulatedData != null)
                  _SimulatedDataView(
                    stageName: widget.stageName,
                    data: _simulatedData!,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Patient card ──────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final VisitModel visit;
  const _PatientCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final patient = visit.patient;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient?.fullName ?? 'Patient #${visit.patientId}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text(patient?.displayId ?? '',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: visit.isPending
                  ? const Color(0xFFE2E8F0)
                  : visit.visitType == 'opd'
                      ? AppColors.primaryTint
                      : AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              visit.visitTypeLabel,
              style: TextStyle(
                color: visit.isPending
                    ? AppColors.textSecondary
                    : visit.visitType == 'opd'
                        ? AppColors.primary
                        : AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simulated data view ───────────────────────────────────────────────────────

class _SimulatedDataView extends StatelessWidget {
  final String stageName;
  final Map<String, dynamic> data;

  const _SimulatedDataView({required this.stageName, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (stageName) {
              'triage'       => 'Vitals',
              'consultation' => 'Clinical Notes',
              'laboratory'   => 'Lab Results',
              'pharmacy'     => 'Prescription',
              _              => 'Record',
            },
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          ..._buildRows(context),
        ],
      ),
    );
  }

  List<Widget> _buildRows(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch (stageName) {
      case 'triage':
        return [
          _Row('Blood Pressure', '${data['bp'] ?? '--'}'),
          _Row('Pulse', '${data['pulse'] ?? '--'} bpm'),
          _Row('Temperature', '${data['temp'] ?? '--'}°C'),
          _Row('Weight', '${data['weight'] ?? '--'} kg'),
          if (data['visit_type_set'] != null)
            _Row('Routed to', '${data['visit_type_set']}'.toUpperCase(),
                bold: true),
        ];
      case 'consultation':
        final prescriptions = (data['prescriptions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return [
          _Row('Diagnosis', '${data['diagnosis'] ?? '--'}'),
          const SizedBox(height: 8),
          Text('Clinical Notes',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('${data['notes'] ?? '--'}',
              style: const TextStyle(fontSize: 14, height: 1.5)),
          if (prescriptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Prescriptions',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            ...prescriptions.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.medication_rounded,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${p['name']} — ${p['dosage']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ];
      case 'laboratory':
        final tests = (data['tests'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return tests.map((t) {
          final isElevated = t['result'] == 'elevated';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${t['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text('${t['value']}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isElevated
                        ? AppColors.errorLight
                        : AppColors.successLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${t['result']}'.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isElevated
                            ? AppColors.error
                            : AppColors.success),
                  ),
                ),
              ],
            ),
          );
        }).toList();
      case 'pharmacy':
        final meds = (data['medications'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return meds.map((m) {
          final dispensed = m['dispensed'] as bool? ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  dispensed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: dispensed ? AppColors.success : cs.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text('${m['dosage']}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList();
      default:
        return [Text(data.toString())];
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _Row(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
