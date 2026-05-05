import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/patient_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_snackbar.dart';

class EmergencyRegistrationScreen extends StatefulWidget {
  const EmergencyRegistrationScreen({super.key});

  @override
  State<EmergencyRegistrationScreen> createState() =>
      _EmergencyRegistrationScreenState();
}

class _EmergencyRegistrationScreenState
    extends State<EmergencyRegistrationScreen> {
  final _service = PatientService();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl   = TextEditingController();
  final _nidaCtrl   = TextEditingController();
  final _dobCtrl    = TextEditingController();
  final _wardCtrl   = TextEditingController();
  final _reasonCtrl = TextEditingController();

  String _gender    = 'male';
  bool _submitting  = false;
  bool _success     = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nidaCtrl.dispose();
    _dobCtrl.dispose();
    _wardCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      await _service.registerPatientEmergency(
        token:  _token,
        name:   _nameCtrl.text.trim(),
        nida:   _nidaCtrl.text.trim(),
        dob:    _dobCtrl.text.trim(),
        gender: _gender,
        ward:   _wardCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
      );
      if (mounted) setState(() { _submitting = false; _success = true; });
    } on PatientException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showStatusSnackbar(context, message: e.message, status: SnackStatus.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        showStatusSnackbar(context,
            message: 'An unexpected error occurred.',
            status: SnackStatus.error);
      }
    }
  }

  void _reset() {
    setState(() {
      _success = false;
      _nameCtrl.clear();
      _nidaCtrl.clear();
      _dobCtrl.clear();
      _wardCtrl.clear();
      _reasonCtrl.clear();
      _gender = 'male';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'EMERGENCY',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Fast Registration'),
          ],
        ),
      ),
      body: _success ? _SuccessView(onReset: _reset) : _FormView(
        formKey: _formKey,
        nameCtrl: _nameCtrl,
        nidaCtrl: _nidaCtrl,
        dobCtrl: _dobCtrl,
        wardCtrl: _wardCtrl,
        reasonCtrl: _reasonCtrl,
        gender: _gender,
        onGenderChanged: (v) { if (v != null) setState(() => _gender = v); },
        submitting: _submitting,
        onSubmit: _submit,
      ),
    );
  }
}

// ── Form ──────────────────────────────────────────────────────────────────────

class _FormView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController nidaCtrl;
  final TextEditingController dobCtrl;
  final TextEditingController wardCtrl;
  final TextEditingController reasonCtrl;
  final String gender;
  final void Function(String?) onGenderChanged;
  final bool submitting;
  final VoidCallback onSubmit;

  const _FormView({
    required this.formKey,
    required this.nameCtrl,
    required this.nidaCtrl,
    required this.dobCtrl,
    required this.wardCtrl,
    required this.reasonCtrl,
    required this.gender,
    required this.onGenderChanged,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fingerprint is optional for emergency registration. '
                      'The patient record will be marked as emergency.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Full Name
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            // NIDA
            TextFormField(
              controller: nidaCtrl,
              decoration: const InputDecoration(
                labelText: 'NIDA Number',
                hintText: 'National ID (optional)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),

            // DOB
            TextFormField(
              controller: dobCtrl,
              decoration: const InputDecoration(
                labelText: 'Date of Birth *',
                hintText: 'YYYY-MM-DD',
                suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
              ),
              keyboardType: TextInputType.datetime,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(1990),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  dobCtrl.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              },
              readOnly: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            // Gender
            DropdownButtonFormField<String>(
              value: gender,
              decoration: const InputDecoration(labelText: 'Gender *'),
              items: const [
                DropdownMenuItem(value: 'male',   child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
              ],
              onChanged: onGenderChanged,
            ),
            const SizedBox(height: 14),

            // Ward / Room
            TextFormField(
              controller: wardCtrl,
              decoration: const InputDecoration(
                labelText: 'Ward / Room *',
                hintText: 'e.g. Ward 3B, ICU',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            // Reason for emergency
            TextFormField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason for Emergency *',
                hintText: 'Brief description of the emergency',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 5) return 'At least 5 characters';
                return null;
              },
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : onSubmit,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.emergency_rounded, size: 20),
                label: const Text('Register Emergency Patient'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Success view ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final VoidCallback onReset;
  const _SuccessView({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Text('Patient Registered',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 10),
            Text(
              'The emergency patient record has been created and marked for follow-up.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onReset,
                child: const Text('Register Another'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
