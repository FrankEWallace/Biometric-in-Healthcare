import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/face_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../camera_screen.dart';

/// Enroll a face template for a patient.
///
/// Can be opened two ways:
///   1. With [patientId] + [patientName] pre-filled (from patient profile).
///   2. Standalone (nurse enters the patient ID manually).
class FaceEnrollScreen extends StatefulWidget {
  /// Pre-fill patient info when navigating from a known patient context.
  final String? patientId;
  final String? patientName;

  const FaceEnrollScreen({
    super.key,
    this.patientId,
    this.patientName,
  });

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  final _patientIdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  XFile?  _capturedImage;
  bool    _isEnrolling = false;
  bool    _success     = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.patientId != null) {
      _patientIdCtrl.text = widget.patientId!;
    }
  }

  @override
  void dispose() {
    _patientIdCtrl.dispose();
    super.dispose();
  }

  bool get _hasPrefilledPatient => widget.patientId != null;

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _openCamera() async {
    if (!_hasPrefilledPatient) {
      final pid = _patientIdCtrl.text.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        setState(() => _error = 'Enter a valid numeric Patient ID first.');
        return;
      }
    }
    setState(() => _error = null);

    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          title: 'Enroll Face',
          showFaceOverlay: true,
          returnImageOnly: true,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _capturedImage = result);
    }
  }

  // ── Enroll ────────────────────────────────────────────────────────────────

  Future<void> _enroll() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_capturedImage == null) {
      setState(() => _error = 'Capture the patient\'s face first.');
      return;
    }

    final token = context.read<AuthProvider>().user?.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Session expired. Please log out and log in again.');
      return;
    }

    setState(() { _isEnrolling = true; _error = null; });

    try {
      await FaceService().enrollFace(
        File(_capturedImage!.path),
        token: token,
        patientId: _patientIdCtrl.text.trim(),
      );

      if (mounted) setState(() { _isEnrolling = false; _success = true; });
    } on FaceException catch (e) {
      if (mounted) setState(() { _error = _errorMessage(e); _isEnrolling = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'An unexpected error occurred.'; _isEnrolling = false; });
    }
  }

  String _errorMessage(FaceException e) {
    switch (e.kind) {
      case FaceErrorKind.network:
        return 'No connection. Check your network and try again.';
      case FaceErrorKind.noFaceDetected:
        return 'No face detected. Look straight at the camera in good lighting.';
      case FaceErrorKind.qualityTooLow:
        return 'Image too blurry. Retake in better lighting.';
      case FaceErrorKind.featureDisabled:
        return 'Facial recognition is not enabled for this hospital.';
      case FaceErrorKind.notFound:
        return 'Patient not found. Verify the Patient ID.';
      case FaceErrorKind.unauthorized:
        return 'Session expired. Please log out and log in again.';
      default:
        return e.message;
    }
  }

  void _reset() => setState(() {
        _capturedImage = null;
        _success       = false;
        _error         = null;
        if (!_hasPrefilledPatient) _patientIdCtrl.clear();
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Face')),
      body: SafeArea(
        child: _isEnrolling
            ? const _EnrollingView()
            : _success
                ? _SuccessView(
                    patientName: widget.patientName ?? 'Patient #${_patientIdCtrl.text}',
                    onDone: () => Navigator.pop(context),
                    onEnrollAnother: _reset,
                  )
                : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error banner
            if (_error != null) ...[
              _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: 16),
            ],

            // Patient ID row (pre-filled or manual)
            if (_hasPrefilledPatient) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.person, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    '${widget.patientName}  ·  #${widget.patientId}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ]),
              ),
            ] else ...[
              const Text('Patient ID',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              CustomTextField(
                controller: _patientIdCtrl,
                label: 'Patient ID',
                hint: 'Enter numeric patient ID',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Patient ID is required.';
                  if (int.tryParse(v.trim()) == null) return 'Must be a number.';
                  return null;
                },
              ),
            ],

            const SizedBox(height: 24),

            // Face capture
            const Text('Patient Face',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            _capturedImage == null
                ? _FacePlaceholder(onTap: _openCamera)
                : _CapturedFace(imagePath: _capturedImage!.path, onRetake: _openCamera),

            const SizedBox(height: 32),

            if (_capturedImage == null)
              PrimaryButton(label: 'Open Camera', icon: Icons.camera_alt, onPressed: _openCamera)
            else ...[
              PrimaryButton(
                label: 'Enroll Face',
                icon: Icons.how_to_reg_rounded,
                onPressed: _isEnrolling ? null : _enroll,
              ),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Retake', icon: Icons.refresh, onPressed: _openCamera),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _EnrollingView extends StatelessWidget {
  const _EnrollingView();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 20),
          Text('Enrolling face template…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        ]),
      );
}

class _SuccessView extends StatelessWidget {
  final String patientName;
  final VoidCallback onDone;
  final VoidCallback onEnrollAnother;

  const _SuccessView({
    required this.patientName,
    required this.onDone,
    required this.onEnrollAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
                color: AppColors.successLight, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 44),
          ),
          const SizedBox(height: 24),
          const Text('Face Enrolled',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Text('Face template for $patientName saved successfully.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.done_rounded),
              label: const Text('Done'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onEnrollAnother,
            child: const Text('Enroll Another Patient'),
          ),
        ],
      ),
    );
  }
}

class _FacePlaceholder extends StatelessWidget {
  final VoidCallback onTap;
  const _FacePlaceholder({required this.onTap});

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
            Icon(Icons.add_a_photo_outlined, size: 52,
                color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text('Tap to capture face',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _CapturedFace extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRetake;
  const _CapturedFace({required this.imagePath, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(File(imagePath),
            width: double.infinity, height: 220, fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(height: 220, color: Colors.black26,
                child: const Icon(Icons.broken_image, color: Colors.white38, size: 48))),
      ),
      Positioned(
        top: 12, left: 12,
        child: _Chip(icon: Icons.face, label: 'Face captured', color: AppColors.success),
      ),
      Positioned(
        top: 12, right: 12,
        child: GestureDetector(
          onTap: onRetake,
          child: _Chip(icon: Icons.refresh, label: 'Retake', color: Colors.white70),
        ),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) => Container(
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
