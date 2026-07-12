import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/patient.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../fingerprint/fingerprint_liveness_camera_screen.dart';
import '../face/face_enroll_screen.dart';

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
    _EnrollStep(hand: 'right', label: 'Right Hand'),
    _EnrollStep(hand: 'left',  label: 'Left Hand'),
  ];

  int _currentIndex = 0;
  bool _uploading   = false;
  String? _error;

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _openCamera() async {
    setState(() => _error = null);
    final result = await Navigator.push<XFile?>(
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

  Future<void> _upload(XFile capture) async {
    setState(() { _uploading = true; _error = null; });
    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      final res = await _fpService.enrollHand(
        File(capture.path),
        token:        _token,
        patientId:    widget.patient.id.toString(),
        hand:         _steps[_currentIndex].hand,
        isPrimary:    _currentIndex == 0,
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );

      if (!mounted) return;

      // Soft notice when the hand enrolled with degraded (< 4) coverage.
      if (res.isPartial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_steps[_currentIndex].label}: enrolled '
                '${res.fingers.length} of 4 fingers — consider re-enrolling later.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }

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
      if (!mounted) return;
      // No usable capture for this hand → offer face enrollment as a fallback.
      if (e.kind == FingerprintErrorKind.noFeatures) {
        await _offerFaceFallback();
      } else {
        setState(() { _uploading = false; _error = e.message; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error     = 'Unexpected error. Please try again.';
        });
      }
    }
  }

  /// When a finger yields no usable capture, offer to enroll the patient's face
  /// instead (the multimodal fallback). The clerk can also retry the finger.
  Future<void> _offerFaceFallback() async {
    setState(() { _uploading = false; });

    final goFace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fingerprint not captured'),
        content: Text(
          'We could not get a usable fingerprint for '
          '${widget.patient.fullName}. You can enroll their face instead, '
          'or try the fingerprint again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Try again'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use face'),
          ),
        ],
      ),
    );

    if (goFace == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FaceEnrollScreen(
            patientId:   widget.patient.id.toString(),
            patientName: widget.patient.fullName,
          ),
        ),
      );
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
  final String hand; // 'right' | 'left'
  final String label;
  const _EnrollStep({required this.hand, required this.label});
}
