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
import '../camera_screen.dart';
import '../ehr_screen.dart';
import '../result_screen.dart';

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
        builder: (_) => CameraScreen(
          title: 'Scan ${_hand == 'right' ? 'Right' : 'Left'} Hand',
          showFingerprintOverlay: true,
          returnImageOnly: true,
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
            ),
          ),
        );
      } else if (result.isNeedsReview) {
        setState(() => _isVerifying = false);
        await _showAdvisoryDialog(result);
        if (mounted) setState(() => _capturedImage = null);
      } else if (result.isAccessRestricted) {
        setState(() => _isVerifying = false);
        await _showAccessRestrictedDialog();
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

  /// access_restricted (plan 005): the patient was identified nationally, but
  /// this facility is not authorized to view their record. The server sends no
  /// PII — never display patient details here.
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
            _ErrorBanner(
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
              _HandOption(
                label: 'Right Hand',
                selected: _hand == 'right',
                onTap: () => setState(() {
                  _hand = 'right';
                  _capturedImage = null;
                }),
              ),
              const SizedBox(width: 12),
              _HandOption(
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
                  child: _Badge(
                      icon: Icons.check_circle,
                      label: 'Captured',
                      color: AppColors.success),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _openCamera,
                    child: const _Badge(
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
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
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
        Text('Segmenting 4 fingers and matching against enrolled patients',
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
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w500)),
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
            child:
                Icon(Icons.error_outline, color: AppColors.error, size: 18)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 13, height: 1.4))),
        GestureDetector(
            onTap: onDismiss,
            child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, color: AppColors.error, size: 16))),
      ]),
    );
  }
}
