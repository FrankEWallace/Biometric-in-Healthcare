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

      setState(() => _step = _RegistrationStep.capturingFingerprint);

      // Immediately open camera after patient is created
      await _openCamera(patient);
    } on PatientException catch (e) {
      setState(() {
        _apiError = e.message;
        _step = _RegistrationStep.form;
      });
    }
  }

  // ── Step 2: open camera — upload handled inside CameraScreen ────────────

  Future<void> _openCamera(PatientModel patient) async {
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          title: 'Capture Fingerprint',
          showFingerprintOverlay: true,
          patientId: patient.id.toString(),
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      // Upload succeeded — go to success screen
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
    } else {
      // User cancelled camera — stay on screen, allow retry
      setState(() => _step = _RegistrationStep.form);
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step progress bar
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
            'Fill in the patient\'s details, then capture their fingerprint.',
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),

          // API error banner
          if (_apiError != null) ...[
            _ErrorBanner(message: _apiError!, onDismiss: () {
              setState(() => _apiError = null);
            }),
            const SizedBox(height: 16),
          ],

          // Form
          Form(
            key: _formKey,
            child: Column(
              children: [
                // Full name
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

                // Date of birth — tappable field
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: CustomTextField(
                      label: 'Date of Birth *',
                      hint: 'DD/MM/YYYY',
                      controller: TextEditingController()..text = _formattedDob,
                      prefixIcon: Icons.cake_outlined,
                      validator: (_) => _dateOfBirth == null
                          ? 'Date of birth is required'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Phone
                CustomTextField(
                  label: 'Phone Number',
                  hint: '+387 61 000 000',
                  controller: _phoneController,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                // JMBG
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

                // Gender dropdown
                _GenderDropdown(
                  value: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Info note
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
                    'After saving patient details you will be directed to capture the fingerprint.',
                    style: TextStyle(
                        color: AppColors.primary, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          PrimaryButton(
            label: 'Save & Capture Fingerprint',
            icon: Icons.arrow_forward,
            onPressed: _submitForm,
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

class _GenderDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _GenderDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Gender',
        prefixIcon: Icon(Icons.wc_outlined,
            color: AppColors.textSecondary, size: 20),
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Prefer not to say')),
        DropdownMenuItem(value: 'male', child: Text('Male')),
        DropdownMenuItem(value: 'female', child: Text('Female')),
        DropdownMenuItem(value: 'other', child: Text('Other')),
      ],
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
      children: List.generate(steps.length, (i) {
        final done = i < current;
        final active = i == current;
        final color = (done || active) ? AppColors.primary : AppColors.divider;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                style: TextStyle(
                  fontSize: 10,
                  color: active
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
