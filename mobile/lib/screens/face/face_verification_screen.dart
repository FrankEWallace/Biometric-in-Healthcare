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
import 'liveness_camera_screen.dart';
import '../ehr_screen.dart';
import '../result_screen.dart';
import '../../widgets/access_restricted_dialog.dart';
import '../../widgets/capture_badge.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/verifying_view.dart';

/// Hospital-wide face identification.
///
/// No patient ID required — the backend searches all enrolled face
/// templates for the hospital and returns the best match.
class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  XFile? _capturedImage;
  bool   _isVerifying = false;
  String? _error;

  static const int _maxAttempts = 3;
  int _attemptCount = 0;

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _openCamera() async {
    setState(() => _error = null);

    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessCameraScreen()),
    );

    if (result != null && mounted) {
      setState(() {
        _capturedImage = result;
        _attemptCount  = 0;
      });
    }
  }

  // ── Verify ────────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (_capturedImage == null) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Session expired. Please log out and log in again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error       = null;
      _attemptCount++;
    });

    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      final result = await FaceService().verifyFace(
        File(_capturedImage!.path),
        token:        token,
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );

      if (!mounted) return;

      if (result.isError) {
        if (mounted) setState(() { _error = 'A server error occurred. Please try again.'; _isVerifying = false; });
      } else if (result.isMatch) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EhrScreen(
              patientName:   result.patientName,
              score:         result.score * 100,
              matchedFinger: 'face',
              ehr:           result.ehr,
              insurance:     result.insurance,
            ),
          ),
        );
      } else if (result.isNeedsReview) {
        // Borderline score — ask staff to confirm manually
        setState(() => _isVerifying = false);
        final confirmed = await _showReviewDialog(result);
        if (!mounted) return;
        if (confirmed == true) {
          // Record the manual confirmation before navigating away
          try {
            if (result.logId != null) {
              await FaceService().confirmManualReview(
                token:     token,
                logId:     result.logId!,
                patientId: result.patientId,
              );
            }
          } catch (_) {
            // Non-blocking — audit failure should not block patient care
          }
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EhrScreen(
                patientName:   result.patientName,
                score:         result.score * 100,
                matchedFinger: 'face',
                ehr:           result.ehr,
                insurance:     result.insurance,
              ),
            ),
          );
        } else {
          setState(() => _capturedImage = null);
        }
      } else if (result.isAccessRestricted) {
        // Identity resolved nationally, but this facility isn't authorized to
        // view the record (plan 005). No PII is present — show a lock message.
        setState(() => _isVerifying = false);
        await showAccessRestrictedDialog(context);
        if (mounted) setState(() => _capturedImage = null);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              isSuccess:      false,
              isRegistration: false,
              patientName:    null,
              patientId:      null,
              score:          result.score * 100,
              matchedFinger:  'face',
              attemptCount:   _attemptCount,
              maxAttempts:    _maxAttempts,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _isVerifying   = false;
            _capturedImage = null;
          });
        }
      }
    } on FaceException catch (e) {
      if (mounted) setState(() { _error = _errorMessage(e); _isVerifying = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'An unexpected error occurred.'; _isVerifying = false; });
    }
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

  Future<bool?> _showReviewDialog(FaceVerifyResult result) {
    final scoreLabel = '${(result.score * 100).toStringAsFixed(1)}%';
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
              'The face match score is borderline. Please verify the patient\'s ID card before proceeding.',
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
                  Text('Similarity score: $scoreLabel',
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

  /// access_restricted (plan 005): patient identified nationally, but this
  /// facility is not authorized to view their record. The server sends no PII.

  void _retake() => setState(() { _capturedImage = null; _error = null; });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification')),
      body: SafeArea(
        child: _isVerifying
            ? const VerifyingView(
                title: 'Identifying patient…',
                subtitle: 'Comparing against enrolled faces')
            : _buildContent(),
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
                    'Point the camera at the patient\'s face. The system will identify them automatically — no ID entry needed.',
                    style: TextStyle(color: AppColors.primary, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Error banner
          if (_error != null) ...[
            ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
            const SizedBox(height: 16),
          ],

          // Face capture area
          const Text('Patient Face',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),

          _capturedImage == null
              ? _FaceScanPrompt(onTap: _openCamera)
              : _CapturedPreview(imagePath: _capturedImage!.path, onRetake: _retake),

          const SizedBox(height: 32),

          if (_capturedImage == null)
            PrimaryButton(label: 'Scan Face', icon: Icons.face, onPressed: _openCamera)
          else
            PrimaryButton(
              label: 'Identify Patient',
              icon: Icons.verified_user_rounded,
              onPressed: _isVerifying ? null : _verify,
            ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────


class _FaceScanPrompt extends StatelessWidget {
  final VoidCallback onTap;
  const _FaceScanPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face, size: 64, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text('Tap to open camera',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _CapturedPreview extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRetake;
  const _CapturedPreview({required this.imagePath, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(File(imagePath),
              width: double.infinity, height: 220, fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                  height: 220,
                  color: Colors.black26,
                  child: const Icon(Icons.broken_image, color: Colors.white38, size: 48))),
        ),
        Positioned(
          top: 12, left: 12,
          child: CaptureBadge(
              icon: Icons.check_circle, label: 'Captured', color: AppColors.success),
        ),
        Positioned(
          top: 12, right: 12,
          child: GestureDetector(
            onTap: onRetake,
            child: CaptureBadge(icon: Icons.refresh, label: 'Retake', color: Colors.white70),
          ),
        ),
      ],
    );
  }
}


