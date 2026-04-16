import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/fingerprint_service.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
import 'ehr_screen.dart';
import 'result_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _patientIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  XFile? _capturedImage;
  bool _isVerifying = false;
  String? _error;

  @override
  void dispose() {
    _patientIdController.dispose();
    super.dispose();
  }

  // ── Step 1: open camera in capture-only mode ──────────────────────────────

  Future<void> _openCamera() async {
    final pid = _patientIdController.text.trim();
    if (pid.isEmpty || int.tryParse(pid) == null) {
      setState(() => _error = 'Enter a valid numeric Patient ID first.');
      return;
    }

    setState(() => _error = null);

    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          title: 'Capture Fingerprint',
          showFingerprintOverlay: true,
          returnImageOnly: true,   // caller handles API call
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _capturedImage = result);
    }
  }

  // ── Step 2: send to Laravel → Python → return verdict ────────────────────

  Future<void> _verify() async {
    if (_capturedImage == null) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() => _error =
          'Your session has expired. Please log out and log in again.');
      return;
    }

    final patientId = _patientIdController.text.trim();

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final result = await FingerprintService().verifyFingerprint(
        File(_capturedImage!.path),
        token: token,
        patientId: patientId,
      );

      if (!mounted) return;

      if (result.isMatch) {
        // Navigate to EHR screen — shows GoT-HoMIS record + insurance
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EhrScreen(
              patientName:   result.patientName,
              score:         result.score,
              matchedFinger: result.matchedFinger,
              ehr:           result.ehr,
              insurance:     result.insurance,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              isSuccess:     false,
              isRegistration: false,
              patientName:   result.patientName,
              patientId:     'ID: ${result.patientId}',
              score:         result.score,
              matchedFinger: result.matchedFinger,
            ),
          ),
        );
      }
    } on FingerprintException catch (e) {
      if (mounted) {
        setState(() {
          _error = _verifyErrorMessage(e);
          _isVerifying = false;
        });
      }
    } catch (_) {
      // Catch unexpected errors (e.g., file read failure) so the screen never
      // gets stuck on the "Verifying…" spinner.
      if (mounted) {
        setState(() {
          _error = 'An unexpected error occurred. Please try again.';
          _isVerifying = false;
        });
      }
    }
  }

  /// Returns an actionable, user-facing message for each error kind.
  String _verifyErrorMessage(FingerprintException e) {
    switch (e.kind) {
      case FingerprintErrorKind.network:
        return 'No connection. Check your network and tap Verify again.';
      case FingerprintErrorKind.qualityTooLow:
        return 'The captured image is too blurry. Tap Retake, move to better '
            'lighting, and try again.';
      case FingerprintErrorKind.noFeatures:
        return 'No fingerprint features were detected. Tap Retake, ensure the '
            'finger fully covers the frame, and try again.';
      case FingerprintErrorKind.serviceUnavailable:
        return 'The fingerprint processing service is temporarily unavailable. '
            'Please wait a moment and try again.';
      case FingerprintErrorKind.notFound:
        return 'Patient not found or no fingerprint enrolled. '
            'Verify the patient ID and ensure a fingerprint has been registered.';
      case FingerprintErrorKind.unauthorized:
        return 'Your session has expired. Please log out and log in again.';
      case FingerprintErrorKind.serverError:
        return 'A server error occurred. Please try again or contact support '
            'if the problem persists.';
      default:
        return e.message;
    }
  }

  void _retake() => setState(() {
        _capturedImage = null;
        _error = null;
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Patient')),
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Instruction banner ──────────────────────────────────────
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
                  Icon(Icons.info_outline,
                      color: AppColors.primary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Enter the patient\'s ID, then capture their fingerprint to verify identity.',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Error banner ────────────────────────────────────────────
            if (_error != null) ...[
              _ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
                // Show retry only when an image is already captured so the
                // user can attempt again without going back to the camera.
                onRetry: _capturedImage != null ? _verify : null,
              ),
              const SizedBox(height: 16),
            ],

            // ── Patient ID field ────────────────────────────────────────
            const Text(
              'Patient ID',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _patientIdController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter numeric patient ID',
                prefixIcon: const Icon(Icons.badge_outlined,
                    color: AppColors.textSecondary, size: 20),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.divider, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.divider, width: 1),
                ),
              ),
              onChanged: (_) {
                // clear image if ID changes after capture
                if (_capturedImage != null) {
                  setState(() => _capturedImage = null);
                }
              },
            ),
            const SizedBox(height: 24),

            // ── Fingerprint capture section ─────────────────────────────
            const Text(
              'Fingerprint',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            if (_capturedImage == null)
              _ScanPrompt(onTap: _openCamera)
            else
              _CapturedPreview(
                imagePath: _capturedImage!.path,
                onRetake: _retake,
              ),

            const SizedBox(height: 32),

            // ── Action buttons ──────────────────────────────────────────
            if (_capturedImage != null)
              PrimaryButton(
                label: 'Verify Identity',
                icon: Icons.verified_user_rounded,
                onPressed: _isVerifying ? null : _verify,
              ),

            if (_capturedImage == null)
              PrimaryButton(
                label: 'Scan Fingerprint',
                icon: Icons.fingerprint,
                onPressed: _openCamera,
              ),
          ],
        ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 20),
          Text(
            'Verifying fingerprint…',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'Comparing against stored template',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ScanPrompt extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fingerprint,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap to capture fingerprint',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapturedPreview extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRetake;

  const _CapturedPreview(
      {required this.imagePath, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(imagePath),
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => Container(
              height: 220,
              color: Colors.black26,
              child: const Icon(Icons.broken_image,
                  color: Colors.white38, size: 48),
            ),
          ),
        ),
        // Success badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 14),
                SizedBox(width: 5),
                Text('Captured',
                    style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        // Retake button
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: onRetake,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white70, size: 14),
                  SizedBox(width: 5),
                  Text('Retake',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  /// When provided, shows a "Retry" button inside the banner.
  final VoidCallback? onRetry;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline,
                    color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13, height: 1.4),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, color: AppColors.error, size: 16),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
