import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/face_service.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../face/liveness_camera_screen.dart';
import '../fingerprint/fingerprint_liveness_camera_screen.dart';
import '../ehr_screen.dart';
import '../result_screen.dart';

/// Multi-modal patient identification — the decision-matrix flow.
///
/// Captures a live face (active liveness) and a fingerprint, then sends both
/// to `POST /api/verify/multimodal`. The backend runs a face shortlist and
/// confirms with a 1:few fingerprint match, returning one of:
///   matched       — both modalities agree → open the record
///   needs_review  — face found a candidate but fingerprint could not confirm
///                   → staff confirms against the ID card before proceeding
///   no_match      — no usable candidate
class MultimodalVerificationScreen extends StatefulWidget {
  const MultimodalVerificationScreen({super.key});

  @override
  State<MultimodalVerificationScreen> createState() =>
      _MultimodalVerificationScreenState();
}

class _MultimodalVerificationScreenState
    extends State<MultimodalVerificationScreen> {
  XFile? _faceImage;
  XFile? _fingerprintImage;
  String _hand = 'right';
  bool _isVerifying = false;
  String? _error;

  static const int _maxAttempts = 3;
  int _attemptCount = 0;

  bool get _ready => _faceImage != null && _fingerprintImage != null;

  // ── Capture steps ───────────────────────────────────────────────────────────

  Future<void> _captureFace() async {
    setState(() => _error = null);
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessCameraScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _faceImage = result;
        _attemptCount = 0;
      });
    }
  }

  Future<void> _captureFingerprint() async {
    setState(() => _error = null);
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintLivenessCameraScreen(
          isHandCapture: true,
          fingerLabel: _hand == 'right' ? 'Right Hand' : 'Left Hand',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _fingerprintImage = result;
        _attemptCount = 0;
      });
    }
  }

  // ── Verify ────────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (!_ready) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Session expired. Please log out and log in again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
      _attemptCount++;
    });

    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      final result = await FaceService().verifyMultimodal(
        faceImage:        File(_faceImage!.path),
        fingerprintImage: File(_fingerprintImage!.path),
        token:            token,
        hand:             _hand,
        gpsLatitude:      position?.latitude,
        gpsLongitude:     position?.longitude,
        wifiSsid:         wifiSsid,
      );

      if (!mounted) return;

      if (result.isMatch) {
        _openRecord(result, score: result.fingerprintScore);
      } else if (result.isNeedsReview) {
        setState(() => _isVerifying = false);
        final confirmed = await _showReviewDialog(result);
        if (!mounted) return;
        if (confirmed == true) {
          // Record the manual confirmation before navigating away.
          try {
            if (result.logId != null) {
              await FaceService().confirmManualReview(
                token: token,
                logId: result.logId!,
                patientId: result.patientId,
              );
            }
          } catch (_) {
            // Non-blocking — an audit failure must not block patient care.
          }
          if (!mounted) return;
          _openRecord(result, score: result.faceScore * 100);
        } else {
          // Try again — keep the face, re-capture the fingerprint.
          setState(() => _fingerprintImage = null);
        }
      } else if (result.isAccessRestricted) {
        setState(() => _isVerifying = false);
        await _showAccessRestrictedDialog();
        if (mounted) setState(() => _fingerprintImage = null);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              isSuccess: false,
              isRegistration: false,
              patientName: null,
              patientId: null,
              score: result.faceScore * 100,
              matchedFinger: 'multimodal',
              attemptCount: _attemptCount,
              maxAttempts: _maxAttempts,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _fingerprintImage = null;
          });
        }
      }
    } on FaceException catch (e) {
      if (mounted) setState(() { _error = _errorMessage(e); _isVerifying = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'An unexpected error occurred.'; _isVerifying = false; });
    }
  }

  void _openRecord(MultimodalVerifyResult result, {required double score}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EhrScreen(
          patientName: result.patientName,
          score: score,
          matchedFinger: 'face + fingerprint',
          ehr: result.ehr,
          insurance: result.insurance,
        ),
      ),
    );
  }

  String _errorMessage(FaceException e) {
    switch (e.kind) {
      case FaceErrorKind.network:
        return 'No connection. Check your network and try again.';
      case FaceErrorKind.noFaceDetected:
        return 'No face detected. Look straight at the camera in good lighting and retake.';
      case FaceErrorKind.qualityTooLow:
        return 'Image too blurry. Move to better lighting and retake.';
      case FaceErrorKind.featureDisabled:
        return 'Facial recognition is not enabled for this hospital.';
      case FaceErrorKind.serviceUnavailable:
        return 'Processing service temporarily unavailable. Please try again.';
      case FaceErrorKind.unauthorized:
        return 'Session expired. Please log out and log in again.';
      case FaceErrorKind.serverError:
        return 'A server error occurred. Please try again.';
      default:
        return e.message;
    }
  }

  /// access_restricted (ADR-013 / plan 019): the patient was identified
  /// nationally, but this facility is not authorized to view their record. The
  /// server sends no PII — never display patient details here.
  Future<void> _showAccessRestrictedDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline, color: Color(0xFF6B7280), size: 22),
          SizedBox(width: 8),
          Text('Access Restricted'),
        ]),
        content: const Text(
          'This patient was identified, but they are registered at another '
          'facility. You are not authorized to view their records here. '
          'Request access through a referral or the patient\'s consent.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showReviewDialog(MultimodalVerifyResult result) {
    final faceLabel = '${(result.faceScore * 100).toStringAsFixed(1)}%';
    final fpLabel = result.fingerprintScore.toStringAsFixed(1);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
          SizedBox(width: 8),
          Text('Manual Review Required'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The face matched a patient but the fingerprint did not confirm it. '
              'Verify the patient\'s ID card before proceeding.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Candidate: ${result.patientName}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Face similarity: $faceLabel   ·   Fingerprint score: $fpLabel',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Try Again'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Manually'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identify Patient')),
      body: SafeArea(
        child: _isVerifying ? const _VerifyingView() : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Capture the patient\'s face, then their fingerprint. The system '
                    'finds the patient by face and confirms with the fingerprint — no '
                    'ID entry needed.',
                    style: TextStyle(color: AppColors.primary, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
            const SizedBox(height: 16),
          ],

          // Step 1 — face
          _CaptureStep(
            step: 1,
            label: 'Patient Face',
            icon: Icons.face,
            imagePath: _faceImage?.path,
            onCapture: _captureFace,
            onRetake: () => setState(() => _faceImage = null),
          ),
          const SizedBox(height: 20),

          // Step 2 — fingerprint
          _CaptureStep(
            step: 2,
            label: 'Fingerprint',
            icon: Icons.fingerprint,
            imagePath: _fingerprintImage?.path,
            onCapture: _captureFingerprint,
            // Capturing the face first keeps the two-step order clear.
            enabled: _faceImage != null,
            onRetake: () => setState(() => _fingerprintImage = null),
          ),

          // Hand selector — only relevant once the face step is done and before
          // the hand is captured (changing it invalidates the current capture).
          if (_faceImage != null && _fingerprintImage == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _HandOption(
                  label: 'Right Hand',
                  selected: _hand == 'right',
                  onTap: () => setState(() => _hand = 'right'),
                ),
                const SizedBox(width: 12),
                _HandOption(
                  label: 'Left Hand',
                  selected: _hand == 'left',
                  onTap: () => setState(() => _hand = 'left'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),

          PrimaryButton(
            label: 'Identify Patient',
            icon: Icons.verified_user_rounded,
            onPressed: _ready && !_isVerifying ? _verify : null,
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _HandOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HandOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.back_hand_outlined,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureStep extends StatelessWidget {
  final int step;
  final String label;
  final IconData icon;
  final String? imagePath;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final bool enabled;

  const _CaptureStep({
    required this.step,
    required this.label,
    required this.icon,
    required this.imagePath,
    required this.onCapture,
    required this.onRetake,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final captured = imagePath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: captured ? AppColors.success : AppColors.primary.withValues(alpha: 0.15),
              ),
              child: captured
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : Center(
                      child: Text('$step',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 12),
        if (!captured)
          Opacity(
            opacity: enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !enabled,
              child: GestureDetector(
                onTap: onCapture,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 52, color: AppColors.primary.withValues(alpha: 0.6)),
                      const SizedBox(height: 12),
                      Text(enabled ? 'Tap to capture' : 'Capture the face first',
                          style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(imagePath!),
                    width: double.infinity, height: 200, fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                        height: 200,
                        color: Colors.black26,
                        child: const Icon(Icons.broken_image, color: Colors.white38, size: 48))),
              ),
              Positioned(
                top: 12, left: 12,
                child: _Badge(icon: Icons.check_circle, label: 'Captured', color: AppColors.success),
              ),
              Positioned(
                top: 12, right: 12,
                child: GestureDetector(
                  onTap: onRetake,
                  child: _Badge(icon: Icons.refresh, label: 'Retake', color: Colors.white70),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _VerifyingView extends StatelessWidget {
  const _VerifyingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.primary),
        SizedBox(height: 20),
        Text('Identifying patient…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        SizedBox(height: 6),
        Text('Matching face, then confirming fingerprint',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: AppColors.error, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: const TextStyle(color: AppColors.error, fontSize: 13, height: 1.4))),
        GestureDetector(
            onTap: onDismiss,
            child: const Padding(padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, color: AppColors.error, size: 16))),
      ]),
    );
  }
}
