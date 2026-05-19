import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/patient.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../fingerprint/fingerprint_liveness_camera_screen.dart';

/// Captures and enrolls fingerprints for an already-registered patient
/// who has no biometric on file.
class FingerprintEnrollScreen extends StatefulWidget {
  final PatientModel patient;
  const FingerprintEnrollScreen({super.key, required this.patient});

  @override
  State<FingerprintEnrollScreen> createState() =>
      _FingerprintEnrollScreenState();
}

class _FingerprintEnrollScreenState extends State<FingerprintEnrollScreen> {
  final _fpService = FingerprintService();

  static const _steps = [
    _EnrollStep(position: 'right_hand', label: 'Right Hand'),
    _EnrollStep(position: 'left_hand',  label: 'Left Hand'),
  ];

  int _currentIndex = 0;
  bool _uploading   = false;
  String? _error;

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _openCamera() async {
    setState(() => _error = null);
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintLivenessCameraScreen(
          isHandCapture: true,
          fingerLabel: _steps[_currentIndex].label,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _upload(result);
  }

  Future<void> _upload(XFile image) async {
    setState(() { _uploading = true; _error = null; });
    try {
      await _fpService.registerFingerprint(
        File(image.path),
        token:          _token,
        patientId:      widget.patient.id.toString(),
        fingerPosition: _steps[_currentIndex].position,
        isPrimary:      _currentIndex == 0,
      );

      if (!mounted) return;

      final next = _currentIndex + 1;
      if (next < _steps.length) {
        setState(() { _currentIndex = next; _uploading = false; });
      } else {
        // All hands enrolled
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Fingerprint enrolled for ${widget.patient.fullName}.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } on FingerprintException catch (e) {
      if (mounted) setState(() { _uploading = false; _error = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error     = 'Unexpected error. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final step   = _steps[_currentIndex];
    final done   = _currentIndex;
    final total  = _steps.length;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Enroll Fingerprint')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient card
              Container(
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
                          Text(widget.patient.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(widget.patient.displayId,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Progress header
              Text(
                'Capture Hand ${done + 1} of $total — ${step.label}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 6,
                  backgroundColor: cs.outlineVariant,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.success),
                ),
              ),
              const SizedBox(height: 24),

              // Step list
              ...List.generate(_steps.length, (i) {
                final isDone   = i < _currentIndex;
                final isActive = i == _currentIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary.withValues(alpha: 0.07)
                          : isDone
                              ? AppColors.success.withValues(alpha: 0.06)
                              : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : isDone
                                ? AppColors.success.withValues(alpha: 0.35)
                                : cs.outline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? AppColors.success
                                : isActive
                                    ? AppColors.primary
                                    : cs.outlineVariant,
                          ),
                          child: isDone
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 15)
                              : isActive
                                  ? const Icon(Icons.back_hand_outlined,
                                      color: Colors.white, size: 15)
                                  : Center(
                                      child: Text('${i + 1}',
                                          style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _steps[i].label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isDone
                                ? AppColors.success
                                : isActive
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isActive) ...[
                          const Spacer(),
                          const Text('Current',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                );
              }),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
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
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              PrimaryButton(
                label: _uploading
                    ? 'Uploading…'
                    : 'Photograph ${step.label}',
                icon: Icons.camera_alt,
                onPressed: _uploading ? null : _openCamera,
                isLoading: _uploading,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrollStep {
  final String position;
  final String label;
  const _EnrollStep({required this.position, required this.label});
}
