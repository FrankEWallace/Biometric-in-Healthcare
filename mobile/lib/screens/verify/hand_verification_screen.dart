import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../ehr_screen.dart';
import '../fingerprint/fingerprint_liveness_camera_screen.dart';
import '../result_screen.dart';
import '../../widgets/access_restricted_dialog.dart';
import '../../widgets/capture_badge.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/hand_option.dart';
import '../../widgets/verifying_view.dart';

/// Four-finger ("hand slap") patient identification.
///
/// One photo of the patient's hand → `POST /api/verify/hand`. The server
/// segments 4 finger crops, matches each against every enrolled hand in the
/// hospital, and fuses the scores into one decision:
///   matched       — open the record
///   needs_review  — advisory candidate only (matcher placeholder or no
///                   calibrated threshold) → staff confirms against ID card
///   no_match      — no enrolled hand crossed the threshold
class HandVerificationScreen extends StatefulWidget {
  const HandVerificationScreen({super.key});

  @override
  State<HandVerificationScreen> createState() => _HandVerificationScreenState();
}

class _HandVerificationScreenState extends State<HandVerificationScreen> {
  String _hand = 'right';
  XFile? _capturedImage;
  bool _isVerifying = false;
  String? _error;

  static const int _maxAttempts = 3;
  int _attemptCount = 0;

  // ── Step 1: capture the hand ────────────────────────────────────────────

  Future<void> _openCamera() async {
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
      setState(() => _capturedImage = result);
    }
  }

  // ── Step 2: identify ────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (_capturedImage == null) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() =>
          _error = 'Your session has expired. Please log out and log in again.');
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

      final result = await FingerprintService().verifyHand(
        File(_capturedImage!.path),
        token:        token,
        hand:         _hand,
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );

      if (!mounted) return;

      if (result.isMatch) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EhrScreen(
              patientName:   result.patient?['full_name'] as String? ?? 'Patient',
              score:         result.score,
              matchedFinger: '4-finger fused ($_hand hand)',
              ehr:           null,
              insurance:     null,
              perFinger:     result.perFinger,
            ),
          ),
        );
      } else if (result.isNeedsReview) {
        setState(() => _isVerifying = false);
        await _showAdvisoryDialog(result);
        if (mounted) setState(() => _capturedImage = null);
      } else if (result.isAccessRestricted) {
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
              score:          result.score,
              matchedFinger:  '4-finger fused',
              attemptCount:   _attemptCount,
              maxAttempts:    _maxAttempts,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _capturedImage = null;
          });
        }
      }
    } on FingerprintException catch (e) {
      if (mounted) {
        setState(() {
          _error = _verifyErrorMessage(e);
          _isVerifying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'An unexpected error occurred. Please try again.';
          _isVerifying = false;
        });
      }
    }
  }

  /// needs_review means the backend could not auto-decide (placeholder
  /// matcher or missing threshold) — surface the advisory candidate and the
  /// server's note; staff must verify identity another way.
  Future<void> _showAdvisoryDialog(HandVerifyResult result) {
    return showDialog<void>(
      context: context,
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
            Text(
              result.note ??
                  'The system could not decide automatically. Verify the '
                      'patient\'s identity with their ID card.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (result.candidatePatientId != null) ...[
              const SizedBox(height: 12),
              Text(
                'Best candidate: patient #${result.candidatePatientId} '
                '(fused score ${result.score.toStringAsFixed(1)})',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ],
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

  String _verifyErrorMessage(FingerprintException e) {
    switch (e.kind) {
      case FingerprintErrorKind.network:
        return e.message;
      case FingerprintErrorKind.qualityTooLow:
        return 'Too few usable fingers in the photo. Hold the hand flat, '
            'fingers spread, in good light — and retake.';
      case FingerprintErrorKind.noFeatures:
        return 'No hand detected. Fill the frame with the four fingers and retake.';
      case FingerprintErrorKind.serviceUnavailable:
        return 'Processing service temporarily unavailable. Please try again.';
      case FingerprintErrorKind.unauthorized:
        return 'Session expired. Please log out and log in again.';
      case FingerprintErrorKind.serverError:
        return 'A server error occurred. Please try again.';
      default:
        return e.message;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identify by Hand')),
      body: SafeArea(
        child: _isVerifying
            ? const VerifyingView(
                title: 'Identifying patient…',
                subtitle:
                    'Segmenting 4 fingers and matching against enrolled patients')
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
                    'Photograph the patient\'s four fingers (no thumb). The '
                    'system matches all four against enrolled patients — no '
                    'ID entry needed.',
                    style: TextStyle(
                        color: AppColors.primary, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
            const SizedBox(height: 16),
          ],

          // Hand selector
          const Text('Which hand?',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              HandOption(
                label: 'Right Hand',
                selected: _hand == 'right',
                onTap: () => setState(() {
                  _hand = 'right';
                  _capturedImage = null;
                }),
              ),
              const SizedBox(width: 12),
              HandOption(
                label: 'Left Hand',
                selected: _hand == 'left',
                onTap: () => setState(() {
                  _hand = 'left';
                  _capturedImage = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Capture area
          if (_capturedImage == null)
            GestureDetector(
              onTap: _openCamera,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1923),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.back_hand_outlined,
                        size: 52,
                        color: AppColors.primary.withValues(alpha: 0.6)),
                    const SizedBox(height: 12),
                    const Text('Tap to photograph the hand',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(_capturedImage!.path),
                    width: double.infinity,
                    height: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                        height: 240,
                        color: Colors.black26,
                        child: const Icon(Icons.broken_image,
                            color: Colors.white38, size: 48)),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: CaptureBadge(
                      icon: Icons.check_circle,
                      label: 'Captured',
                      color: AppColors.success),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _openCamera,
                    child: const CaptureBadge(
                        icon: Icons.refresh,
                        label: 'Retake',
                        color: Colors.white70),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 32),

          PrimaryButton(
            label: 'Identify Patient',
            icon: Icons.verified_user_rounded,
            onPressed:
                _capturedImage != null && !_isVerifying ? _verify : null,
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────




