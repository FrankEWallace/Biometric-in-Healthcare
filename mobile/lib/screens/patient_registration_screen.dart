import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient.dart';
import '../providers/auth_provider.dart';
import '../services/patient_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
import 'result_screen.dart';

// ── Finger scan steps (Selcom-style, sequential) ─────────────────────────────

class _FingerStep {
  final String position;    // API field value
  final String label;       // Human-readable label shown in camera UI
  final bool isHandCapture; // true → wide hand frame, false → single finger

  const _FingerStep({
    required this.position,
    required this.label,
    this.isHandCapture = false,
  });
}

const _fingerSteps = [
  _FingerStep(
    position: 'right_hand',
    label: 'Right Hand',
    isHandCapture: true,
  ),
  _FingerStep(
    position: 'left_hand',
    label: 'Left Hand',
    isHandCapture: true,
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key});

  @override
  State<PatientRegistrationScreen> createState() =>
      _PatientRegistrationScreenState();
}

enum _RegistrationStep { form, creatingPatient, capturingFingerprint }

class _PatientRegistrationScreenState
    extends State<PatientRegistrationScreen> {
  // Form
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jmbgController = TextEditingController();
  DateTime? _dateOfBirth;
  String? _gender;

  // State
  _RegistrationStep _step = _RegistrationStep.form;
  String? _apiError;

  // Multi-finger tracking
  PatientModel? _createdPatient;
  int _currentFingerIndex = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _jmbgController.dispose();
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
        jmbg: _jmbgController.text.trim(),
      );

      setState(() {
        _createdPatient = patient;
        _currentFingerIndex = 0;
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
    final finger = _fingerSteps[_currentFingerIndex];

    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          title:
              'Scan Hand ${_currentFingerIndex + 1} of ${_fingerSteps.length}',
          showFingerprintOverlay: true,
          patientId: patient.id.toString(),
          fingerPosition: finger.position,
          fingerLabel: finger.label,
          isHandCapture: finger.isHandCapture,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      final nextIndex = _currentFingerIndex + 1;

      if (nextIndex < _fingerSteps.length) {
        // More fingers remain — advance and open camera again
        setState(() => _currentFingerIndex = nextIndex);
        await _openCameraForCurrentFinger(patient);
      } else {
        // All fingers captured — go to success screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              isSuccess: true,
              patientName: patient.fullName,
              patientId: patient.id.toString(),
              isRegistration: true,
            ),
          ),
        );
      }
    } else {
      // User cancelled — allow retry from the finger progress screen
      setState(() => _step = _RegistrationStep.capturingFingerprint);
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

    if (_step == _RegistrationStep.capturingFingerprint &&
        _createdPatient != null) {
      return _FingerProgressView(
        patient: _createdPatient!,
        currentIndex: _currentFingerIndex,
        fingers: _fingerSteps,
        onRetry: () => _openCameraForCurrentFinger(_createdPatient!),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBar(
            steps: const ['Patient Info', 'Fingerprint', 'Complete'],
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
            _ErrorBanner(
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
                  label: 'JMBG (National ID)',
                  hint: '13-digit national ID',
                  controller: _jmbgController,
                  prefixIcon: Icons.badge_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length != 13) {
                      return 'JMBG must be exactly 13 digits';
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
                    'After saving, you will photograph both hands (4 fingers each).',
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
  final List<_FingerStep> fingers;
  final VoidCallback onRetry;

  const _FingerProgressView({
    required this.patient,
    required this.currentIndex,
    required this.fingers,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final finger = fingers[currentIndex];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBar(
            steps: const ['Patient Info', 'Fingerprint', 'Complete'],
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
                    '${patient.fullName}  ·  #${patient.id}',
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
            'Photograph hand ${currentIndex + 1} of ${fingers.length}',
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Finger checklist
          ...List.generate(fingers.length, (i) {
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
                      fingers[i].label,
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
            label: 'Photograph ${finger.label}',
            icon: Icons.camera_alt,
            onPressed: onRetry,
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: AppColors.error, size: 16),
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
