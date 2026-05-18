import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/face_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import 'liveness_camera_screen.dart';
import '../ehr_screen.dart';
import '../result_screen.dart';

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
      final result = await FaceService().verifyFace(
        File(_capturedImage!.path),
        token: token,
      );

      if (!mounted) return;

      if (result.isMatch) {
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

  void _retake() => setState(() { _capturedImage = null; _error = null; });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification')),
      body: SafeArea(
        child: _isVerifying
            ? const _VerifyingView()
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
            _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
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
        Text('Comparing against enrolled faces',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

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
          child: _Badge(
              icon: Icons.check_circle, label: 'Captured', color: AppColors.success),
        ),
        Positioned(
          top: 12, right: 12,
          child: GestureDetector(
            onTap: onRetake,
            child: _Badge(icon: Icons.refresh, label: 'Retake', color: Colors.white70),
          ),
        ),
      ],
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
