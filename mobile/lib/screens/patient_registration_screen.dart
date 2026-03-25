import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/custom_text_field.dart';
import 'fingerprint_capture_screen.dart';

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key});

  @override
  State<PatientRegistrationScreen> createState() =>
      _PatientRegistrationScreenState();
}

class _PatientRegistrationScreenState
    extends State<PatientRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _patientIdController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _patientIdController.dispose();
    super.dispose();
  }

  void _proceedToCapture() {
    if (_formKey.currentState!.validate()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FingerprintCaptureScreen(
            patientName: _nameController.text.trim(),
            patientId: _patientIdController.text.trim(),
            isRegistration: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Patient')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step indicator
              _StepIndicator(currentStep: 1, totalSteps: 3),
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
                'Enter the patient\'s basic details to begin registration.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    CustomTextField(
                      label: 'Full Name',
                      hint: 'e.g. John Doe',
                      controller: _nameController,
                      prefixIcon: Icons.person_outline,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Full name is required';
                        }
                        if (val.trim().length < 3) {
                          return 'Name must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Patient ID',
                      hint: 'e.g. PAT-00123',
                      controller: _patientIdController,
                      prefixIcon: Icons.badge_outlined,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Patient ID is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Phone Number',
                      hint: 'e.g. +387 61 000 000',
                      controller: _phoneController,
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Phone number is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

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
                    Icon(Icons.info_outline,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'After filling in the details, you will be prompted to capture the patient\'s fingerprint.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              PrimaryButton(
                label: 'Next — Capture Fingerprint',
                icon: Icons.arrow_forward,
                onPressed: _proceedToCapture,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator(
      {required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final step = i + 1;
        final isActive = step == currentStep;
        final isDone = step < currentStep;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isActive || isDone)
                        ? AppColors.primary
                        : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (step < totalSteps) const SizedBox(width: 4),
            ],
          ),
        );
      }),
    );
  }
}
