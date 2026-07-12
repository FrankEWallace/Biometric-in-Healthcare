import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient.dart';
import '../providers/auth_provider.dart';
import '../services/face_service.dart';
import '../services/fingerprint_service.dart';
import '../services/location_service.dart';
import '../services/network_service.dart';
import '../services/patient_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import 'fingerprint/fingerprint_liveness_camera_screen.dart';
import 'face/liveness_camera_screen.dart';
import 'result_screen.dart';
import '../widgets/error_banner.dart';

// ── Hand scan steps (four fingers per photo, sequential) ─────────────────────

class _HandStep {
  final String hand;  // API field value: 'right' | 'left'
  final String label; // Human-readable label shown in camera UI

  const _HandStep({required this.hand, required this.label});
}

const _handSteps = [
  _HandStep(hand: 'right', label: 'Right Hand'),
  _HandStep(hand: 'left', label: 'Left Hand'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key});

  @override
  State<PatientRegistrationScreen> createState() =>
      _PatientRegistrationScreenState();
}

enum _RegistrationStep { form, creatingPatient, capturingFingerprint, capturingFace }

class _PatientRegistrationScreenState
    extends State<PatientRegistrationScreen> {
  // Form
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidaController = TextEditingController();
  DateTime? _dateOfBirth;
  String? _gender;

  // State
  _RegistrationStep _step = _RegistrationStep.form;
  String? _apiError;
  String? _faceError;
  bool _faceEnrolling = false;

  // Multi-finger tracking
  PatientModel? _createdPatient;
  int _currentFingerIndex = 0;
  bool _primaryAssigned = false; // first usable finger becomes the 1:N primary
  bool _fingerUploading = false; // saving a finger's gallery to the server

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nidaController.dispose();
    super.dispose();
  }

  // ── Step 1: validate → create patient ────────────────────────────────────

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      setState(() => _apiError = 'Date of birth is required.');
      return;
    }

    setState(() {
      _step = _RegistrationStep.creatingPatient;
      _apiError = null;
    });

    final token = context.read<AuthProvider>().user?.token ?? '';
    final dob =
        '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';

    try {
      final patient = await PatientService().createPatient(
        token: token,
        fullName: _nameController.text.trim(),
        dateOfBirth: dob,
        phone: _phoneController.text.trim(),
        gender: _gender,
        nida: _nidaController.text.trim(),
      );

      setState(() {
        _createdPatient = patient;
        _currentFingerIndex = 0;
        _primaryAssigned = false;
        _step = _RegistrationStep.capturingFingerprint;
      });

      await _openCameraForCurrentFinger(patient);
    } on PatientException catch (e) {
      setState(() {
        _apiError = e.message;
        _step = _RegistrationStep.form;
      });
    }
  }

  // ── Step 2: open camera for each finger sequentially ─────────────────────

  Future<void> _openCameraForCurrentFinger(PatientModel patient) async {
    final handStep = _handSteps[_currentFingerIndex];

    final result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintLivenessCameraScreen(
          isHandCapture: true,
          fingerLabel: handStep.label,
        ),
      ),
    );

    if (!mounted) return;

    if (result == null) {
      // User cancelled — allow retry from the finger progress screen.
      setState(() => _step = _RegistrationStep.capturingFingerprint);
      return;
    }

    await _enrollHand(patient, handStep, result);
  }

  /// Upload one hand photo (server segments 4 fingers), then advance to the
  /// next hand or the face step.
  ///
  /// A hand that yields too few usable fingers is skipped with a notice —
  /// face enrollment is the next step and serves as the multimodal fallback,
  /// so a patient is never blocked. The first successfully enrolled hand
  /// carries the 1:N primary (its index finger).
  Future<void> _enrollHand(
    PatientModel patient,
    _HandStep handStep,
    XFile capture,
  ) async {
    setState(() {
      _fingerUploading = true;
      _apiError = null;
    });

    final token = context.read<AuthProvider>().user?.token ?? '';
    String? notice;

    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      final res = await FingerprintService().enrollHand(
        File(capture.path),
        token:        token,
        patientId:    patient.id.toString(),
        hand:         handStep.hand,
        isPrimary:    !_primaryAssigned,
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );

      _primaryAssigned = true; // a hand is now enrolled
      if (res.isPartial) {
        notice =
            '${handStep.label}: enrolled ${res.fingers.length} of 4 fingers.';
      }
    } on FingerprintException catch (e) {
      if (e.kind == FingerprintErrorKind.noFeatures) {
        // Nothing usable on this hand — skip it; Face ID is next.
        notice =
            '${handStep.label}: no usable fingerprints — Face ID can be used instead.';
      } else {
        if (mounted) {
          setState(() {
            _fingerUploading = false;
            _apiError        = e.message;
            _step            = _RegistrationStep.capturingFingerprint;
          });
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fingerUploading = false;
          _apiError        = 'Unexpected error saving fingerprint. Please try again.';
          _step            = _RegistrationStep.capturingFingerprint;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _fingerUploading = false);

    if (notice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notice), backgroundColor: AppColors.warning),
      );
    }

    final nextIndex = _currentFingerIndex + 1;
    if (nextIndex < _handSteps.length) {
      setState(() => _currentFingerIndex = nextIndex);
      await _openCameraForCurrentFinger(patient);
    } else {
      // All hands processed — move to face enrollment.
      setState(() => _step = _RegistrationStep.capturingFace);
    }
  }

  /// Advance past the current hand without enrolling it (e.g. injury,
  /// bandage, or repeated capture failures). Face ID remains the fallback.
  void _skipCurrentHand() {
    final nextIndex = _currentFingerIndex + 1;
    setState(() {
      _apiError = null;
      if (nextIndex < _handSteps.length) {
        _currentFingerIndex = nextIndex;
      } else {
        _step = _RegistrationStep.capturingFace;
      }
    });
  }

  // ── Step 3: capture face and enroll ──────────────────────────────────────

  Future<void> _captureFace() async {
    setState(() { _faceError = null; });

    final XFile? file = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessCameraScreen()),
    );

    if (!mounted || file == null) return;

    final token = context.read<AuthProvider>().user?.token ?? '';

    setState(() => _faceEnrolling = true);

    try {
      final position = await LocationService().getCurrentPosition();
      final wifiSsid = await NetworkService().getCurrentSsid();

      await FaceService().enrollFace(
        File(file.path),
        token: token,
        patientId: _createdPatient!.id.toString(),
        gpsLatitude:  position?.latitude,
        gpsLongitude: position?.longitude,
        wifiSsid:     wifiSsid,
      );
    } on FaceException catch (e) {
      if (!mounted) return;
      // Face recognition may be disabled for the hospital — treat as non-fatal
      if (e.kind == FaceErrorKind.featureDisabled) {
        _navigateToResult();
        return;
      }
      setState(() { _faceError = _faceErrorMessage(e); _faceEnrolling = false; });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() { _faceError = 'Face enrollment failed. You can skip and enroll later.'; _faceEnrolling = false; });
      return;
    }

    if (!mounted) return;
    _navigateToResult();
  }

  void _skipFaceEnroll() => _navigateToResult();

  void _navigateToResult() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          isSuccess: true,
          patientName: _createdPatient!.fullName,
          patientId: _createdPatient!.displayId,
          isRegistration: true,
        ),
      ),
    );
  }

  String _faceErrorMessage(FaceException e) {
    switch (e.kind) {
      case FaceErrorKind.network:          return 'No connection. Check your network and try again.';
      case FaceErrorKind.noFaceDetected:   return 'No face detected. Look straight at the camera in good lighting.';
      case FaceErrorKind.qualityTooLow:    return 'Image too blurry. Move to better lighting and retake.';
      case FaceErrorKind.unauthorized:     return 'Session expired. Please log out and log in again.';
      default:                             return e.message;
    }
  }

  // ── Date picker ──────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _apiError = null;
      });
    }
  }

  String get _formattedDob {
    if (_dateOfBirth == null) return '';
    return '${_dateOfBirth!.day.toString().padLeft(2, '0')}/'
        '${_dateOfBirth!.month.toString().padLeft(2, '0')}/'
        '${_dateOfBirth!.year}';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Patient')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_step == _RegistrationStep.creatingPatient) {
      return const _LoadingView(message: 'Creating patient record…');
    }

    if (_fingerUploading) {
      return const _LoadingView(message: 'Saving fingerprint…');
    }

    if (_step == _RegistrationStep.capturingFingerprint &&
        _createdPatient != null) {
      return _FingerProgressView(
        patient: _createdPatient!,
        currentIndex: _currentFingerIndex,
        hands: _handSteps,
        error: _apiError,
        onRetry: () => _openCameraForCurrentFinger(_createdPatient!),
        onSkip: _skipCurrentHand,
        onDismissError: () => setState(() => _apiError = null),
      );
    }

    if (_step == _RegistrationStep.capturingFace && _createdPatient != null) {
      return _FaceCaptureView(
        patient: _createdPatient!,
        isEnrolling: _faceEnrolling,
        error: _faceError,
        onCapture: _captureFace,
        onSkip: _skipFaceEnroll,
        onDismissError: () => setState(() => _faceError = null),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBar(
            steps: const ['Patient Info', 'Fingerprint', 'Face ID', 'Complete'],
            current: 0,
          ),
          const SizedBox(height: 28),

          const Text(
            'Patient Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Fill in the patient\'s details, then capture their fingerprints.',
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),

          if (_apiError != null) ...[
            ErrorBanner(
                message: _apiError!,
                onDismiss: () => setState(() => _apiError = null)),
            const SizedBox(height: 16),
          ],

          Form(
            key: _formKey,
            child: Column(
              children: [
                CustomTextField(
                  label: 'Full Name *',
                  hint: 'e.g. Amina Kovač',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline,
                  validator: (v) {
                    if (v == null || v.trim().length < 3) {
                      return 'Enter at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: CustomTextField(
                      label: 'Date of Birth *',
                      hint: 'DD/MM/YYYY',
                      controller: TextEditingController()
                        ..text = _formattedDob,
                      prefixIcon: Icons.cake_outlined,
                      validator: (_) => _dateOfBirth == null
                          ? 'Date of birth is required'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Phone Number',
                  hint: '+387 61 000 000',
                  controller: _phoneController,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'NIDA (National ID)',
                  hint: '20-digit national ID',
                  controller: _nidaController,
                  prefixIcon: Icons.badge_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length != 20) {
                      return 'NIDA must be exactly 20 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _GenderPicker(
                  value: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'After saving, you will photograph both hands (4 fingers each), then capture the patient\'s face.',
                    style: TextStyle(
                        color: AppColors.primary, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          PrimaryButton(
            label: 'Save & Capture Fingerprints',
            icon: Icons.arrow_forward,
            onPressed: _submitForm,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Finger progress screen (shown between camera sessions) ────────────────────

class _FingerProgressView extends StatelessWidget {
  final PatientModel patient;
  final int currentIndex;
  final List<_HandStep> hands;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onSkip;
  final VoidCallback onDismissError;

  const _FingerProgressView({
    required this.patient,
    required this.currentIndex,
    required this.hands,
    required this.onRetry,
    required this.onSkip,
    required this.onDismissError,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final handStep = hands[currentIndex];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBar(
            steps: const ['Patient Info', 'Fingerprint', 'Face ID', 'Complete'],
            current: 1,
          ),
          const SizedBox(height: 28),

          // Patient banner
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${patient.fullName}  ·  ${patient.displayId}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          const Text(
            'Fingerprint Capture',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Photograph hand ${currentIndex + 1} of ${hands.length} — 4 fingers, no thumb',
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          if (error != null) ...[
            ErrorBanner(message: error!, onDismiss: onDismissError),
            const SizedBox(height: 16),
          ],

          // Hand checklist
          ...List.generate(hands.length, (i) {
            final done = i < currentIndex;
            final active = i == currentIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : done
                          ? AppColors.success.withValues(alpha: 0.06)
                          : AppColors.secondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : done
                            ? AppColors.success.withValues(alpha: 0.4)
                            : AppColors.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? AppColors.success
                            : active
                                ? AppColors.primary
                                : AppColors.divider,
                      ),
                      child: done
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 15)
                          : active
                              ? const Icon(Icons.back_hand_outlined,
                                  color: Colors.white, size: 15)
                              : Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      hands[i].label,
                      style: TextStyle(
                        color: active
                            ? AppColors.textPrimary
                            : done
                                ? AppColors.success
                                : AppColors.textHint,
                        fontSize: 14,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (active) ...[
                      const Spacer(),
                      const Text(
                        'Next',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          PrimaryButton(
            label: 'Photograph ${handStep.label}',
            icon: Icons.camera_alt,
            onPressed: onRetry,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: const Text(
                'Skip this hand',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Face capture step ─────────────────────────────────────────────────────────

class _FaceCaptureView extends StatelessWidget {
  final PatientModel patient;
  final bool isEnrolling;
  final String? error;
  final VoidCallback onCapture;
  final VoidCallback onSkip;
  final VoidCallback onDismissError;

  const _FaceCaptureView({
    required this.patient,
    required this.isEnrolling,
    required this.onCapture,
    required this.onSkip,
    required this.onDismissError,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (isEnrolling) {
      return const _LoadingView(message: 'Enrolling face template…');
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBar(
            steps: const ['Patient Info', 'Fingerprint', 'Face ID', 'Complete'],
            current: 2,
          ),
          const SizedBox(height: 28),

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
              Expanded(
                child: Text(
                  '${patient.fullName}  ·  ${patient.displayId}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),

          const Text(
            'Face ID Enrollment',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Capture the patient\'s face for identity verification. The camera will guide you through a liveness check.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),

          if (error != null) ...[
            ErrorBanner(message: error!, onDismiss: onDismissError),
            const SizedBox(height: 16),
          ],

          Container(
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
                Icon(Icons.face_outlined, size: 52,
                    color: AppColors.primary.withValues(alpha: 0.6)),
                const SizedBox(height: 12),
                const Text('Face not yet captured',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),

          const Spacer(),

          PrimaryButton(
            label: 'Open Camera',
            icon: Icons.camera_alt,
            onPressed: onCapture,
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Skip (Enroll Later)',
            icon: Icons.skip_next,
            onPressed: onSkip,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}


/// Two-option gender picker (Male / Female only).
class _GenderPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _GenderPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Gender',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Row(
          children: [
            _GenderOption(
              label: 'Male',
              icon: Icons.male,
              selected: value == 'male',
              onTap: () => onChanged('male'),
            ),
            const SizedBox(width: 12),
            _GenderOption(
              label: 'Female',
              icon: Icons.female,
              selected: value == 'female',
              onTap: () => onChanged('female'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GenderOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

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
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  final List<String> steps;
  final int current;

  const _StepBar({required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final filled = stepIndex < current;
          return Expanded(
            child: Container(
              height: 2,
              color: filled ? AppColors.primary : AppColors.divider,
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final done   = stepIndex < current;
        final active = stepIndex == current;
        final bgColor = done || active ? AppColors.primary : AppColors.divider;
        final labelColor = active
            ? AppColors.primary
            : done
                ? AppColors.textSecondary
                : AppColors.textHint;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                border: active
                    ? Border.all(
                        color: AppColors.primaryLight, width: 2)
                    : null,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Center(
                      child: Text(
                        '${stepIndex + 1}',
                        style: TextStyle(
                          color: active || done
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              steps[stepIndex],
              style: TextStyle(
                fontSize: 10,
                color: labelColor,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }
}
