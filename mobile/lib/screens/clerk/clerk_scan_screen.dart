import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/patient.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../fingerprint/fingerprint_liveness_camera_screen.dart';
import 'clerk_dashboard.dart';

/// Clerk scans the patient's fingerprint to confirm identity, then opens a visit.
class ClerkScanScreen extends StatefulWidget {
  final PatientModel patient;
  const ClerkScanScreen({super.key, required this.patient});

  @override
  State<ClerkScanScreen> createState() => _ClerkScanScreenState();
}

class _ClerkScanScreenState extends State<ClerkScanScreen> {
  final _visitService = VisitService();
  final _fpService    = FingerprintService();

  XFile? _capturedImage;
  bool _isProcessing = false;
  String? _error;
  int _attempts = 0;
  static const int _maxAttempts = 3;

  Future<void> _openCamera() async {
    setState(() => _error = null);
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const FingerprintLivenessCameraScreen(
          isHandCapture: true,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _capturedImage = result);
  }

  Future<void> _scanAndOpen() async {
    if (_capturedImage == null) return;
    if (_attempts >= _maxAttempts) {
      setState(() => _error = 'Too many failed attempts. Request a supervisor override.');
      return;
    }

    final token = context.read<AuthProvider>().user?.token ?? '';
    setState(() { _isProcessing = true; _error = null; _attempts++; });

    try {
      // Step 1: verify fingerprint (four-finger fused) against this specific patient
      final result = await _verifyHandBothSides(File(_capturedImage!.path), token);

      if (result.isAccessRestricted) {
        setState(() {
          _isProcessing = false;
          _error = 'Patient identified, but records are restricted at this facility.';
          _capturedImage = null;
        });
        return;
      }
      if (result.isNeedsReview) {
        setState(() {
          _isProcessing = false;
          _error = 'Could not auto-confirm identity. Verify manually with an '
              'ID card, or contact a supervisor.';
          _capturedImage = null;
        });
        return;
      }

      final matchedPatientId = result.patient?['id'] as int?;
      if (!result.isMatch || matchedPatientId != widget.patient.id) {
        setState(() {
          _isProcessing = false;
          _error = result.isMatch
              ? 'Fingerprint matched a different patient.'
              : _attempts >= _maxAttempts
                  ? 'Verification failed after $_maxAttempts attempts.'
                  : 'Fingerprint did not match. ${_maxAttempts - _attempts} attempt(s) remaining.';
          _capturedImage = null;
        });
        return;
      }

      // Step 2: open the visit using the verification log
      await _visitService.openVisit(
        token: token,
        patientId: widget.patient.id,
        verificationLogId: result.logId!,
      );

      if (!mounted) return;

      // Success — replace the whole navigation stack with the clerk dashboard
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visit opened for ${widget.patient.fullName}'),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ClerkDashboard()),
        (route) => route.isFirst,
      );
    } on FingerprintException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.message;
          _capturedImage = null;
        });
      }
    } on VisitException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.message;
          _capturedImage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Unexpected error. Please try again.';
          _capturedImage = null;
        });
      }
    }
  }

  /// This screen doesn't ask which hand was photographed, so the server scores
  /// both orientations and returns the better match — one 1:N call and one
  /// verification-log row per attempt (previously this fired two separate
  /// /verify/hand calls, doubling the server-side log + throttle spend).
  Future<HandVerifyResult> _verifyHandBothSides(File image, String token) {
    return _fpService.verifyHand(image, token: token, hand: 'both');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Verify & Check In')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient card
              _PatientCard(patient: widget.patient),
              const SizedBox(height: 32),

              Text('Fingerprint Verification',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Scan the patient\'s fingerprint to confirm identity before opening a visit.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),

              // Capture area
              GestureDetector(
                onTap: _isProcessing ? null : _openCamera,
                child: Container(
                  width: double.infinity,
                  height: 160,
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
                                color: AppColors.success, size: 44),
                            const SizedBox(height: 8),
                            const Text('Image captured',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Tap to recapture',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint,
                                size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text('Tap to scan fingerprint',
                                style: TextStyle(color: cs.onSurfaceVariant)),
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

              // Attempts indicator
              if (_attempts > 0 && _attempts < _maxAttempts)
                Center(
                  child: Text(
                    'Attempt $_attempts of $_maxAttempts',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),

              PrimaryButton(
                label: _isProcessing ? 'Verifying…' : 'Verify & Open Visit',
                onPressed: _capturedImage != null && !_isProcessing
                    ? _scanAndOpen
                    : null,
                isLoading: _isProcessing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final PatientModel patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(patient.displayId,
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500)),
                if (patient.dateOfBirth != null) ...[
                  const SizedBox(height: 2),
                  Text('DOB: ${patient.dateOfBirth}',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
