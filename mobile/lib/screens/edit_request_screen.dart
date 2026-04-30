import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/patient_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';

// ── EditRequestScreen ─────────────────────────────────────────────────────────
//
// Used in two modes:
//   reviewMode: false (default) — nurse submits a demographic change request
//   reviewMode: true             — admin/super_admin reviews pending requests

class EditRequestScreen extends StatefulWidget {
  final bool reviewMode;
  const EditRequestScreen({super.key, this.reviewMode = false});

  @override
  State<EditRequestScreen> createState() => _EditRequestScreenState();
}

class _EditRequestScreenState extends State<EditRequestScreen> {
  final _patientService = PatientService();

  // ── Nurse submit state ────────────────────────────────────────────────────
  final _formKey        = GlobalKey<FormState>();
  final _patientIdCtrl  = TextEditingController();
  final _newValueCtrl   = TextEditingController();
  final _reasonCtrl     = TextEditingController();
  String _selectedField = 'full_name';
  bool _submitting      = false;
  String? _submitError;
  bool _submitSuccess   = false;

  // ── Admin review state ────────────────────────────────────────────────────
  bool _loading = false;
  String? _loadError;
  List<Map<String, dynamic>> _requests = [];

  static const _fieldOptions = [
    ('full_name',     'Full Name'),
    ('phone',         'Phone'),
    ('date_of_birth', 'Date of Birth'),
    ('gender',        'Gender'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.reviewMode) _loadRequests();
  }

  @override
  void dispose() {
    _patientIdCtrl.dispose();
    _newValueCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Load pending requests (admin) ─────────────────────────────────────────

  Future<void> _loadRequests() async {
    setState(() { _loading = true; _loadError = null; });
    final token = context.read<AuthProvider>().user!.token;
    try {
      final list = await _patientService.getPendingEditRequests(token: token);
      setState(() { _requests = list; _loading = false; });
    } on PatientException catch (e) {
      setState(() { _loadError = e.message; _loading = false; });
    }
  }

  Future<void> _review(int id, bool approve) async {
    final token = context.read<AuthProvider>().user!.token;
    try {
      await _patientService.reviewEditRequest(
          token: token, editRequestId: id, approve: approve);
      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? 'Request approved.' : 'Request rejected.'),
          backgroundColor:
              approve ? AppColors.success : AppColors.error,
        ));
      }
    } on PatientException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  // ── Submit edit request (nurse) ───────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final patientId = int.tryParse(_patientIdCtrl.text.trim());
    if (patientId == null) {
      setState(() => _submitError = 'Enter a valid patient ID.');
      return;
    }

    setState(() { _submitting = true; _submitError = null; });
    final token = context.read<AuthProvider>().user!.token;

    try {
      await _patientService.submitEditRequest(
        token:     token,
        patientId: patientId,
        field:     _selectedField,
        newValue:  _newValueCtrl.text.trim(),
        reason:    _reasonCtrl.text.trim(),
      );
      setState(() { _submitting = false; _submitSuccess = true; });
    } on PatientException catch (e) {
      setState(() { _submitting = false; _submitError = e.message; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.reviewMode
            ? 'Review Edit Requests'
            : 'Submit Edit Request'),
      ),
      body: widget.reviewMode ? _buildReviewBody() : _buildSubmitBody(),
    );
  }

  // ── Admin review body ─────────────────────────────────────────────────────

  Widget _buildReviewBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(_loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _loadRequests,
                child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 56),
          SizedBox(height: 16),
          Text('No pending requests.',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ReviewCard(
          request: _requests[i],
          onApprove: () => _review(_requests[i]['id'] as int, true),
          onReject:  () => _review(_requests[i]['id'] as int, false),
        ),
      ),
    );
  }

  // ── Nurse submit body ─────────────────────────────────────────────────────

  Widget _buildSubmitBody() {
    if (_submitSuccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.success, size: 42),
            ),
            const SizedBox(height: 24),
            const Text(
              'Request Submitted',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            const Text(
              'An administrator will review and approve the change.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _submitSuccess = false;
                  _patientIdCtrl.clear();
                  _newValueCtrl.clear();
                  _reasonCtrl.clear();
                  _selectedField = 'full_name';
                });
              },
              child: const Text('Submit Another'),
            ),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Request a demographic change for a patient. An administrator must approve it before it takes effect.',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _patientIdCtrl,
            label: 'Patient ID',
            hint: 'Enter numeric patient ID',
            keyboardType: TextInputType.number,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Field selector
          const Text(
            'Field to change',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedField,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                borderRadius: BorderRadius.circular(12),
                items: _fieldOptions
                    .map((f) => DropdownMenuItem(
                          value: f.$1,
                          child: Text(f.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedField = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _newValueCtrl,
            label: 'New Value',
            hint: 'Enter the corrected value',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _reasonCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason',
              hintText: 'Explain why this change is needed (min 10 chars)',
              alignLabelWithHint: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 10) return 'At least 10 characters required';
              return null;
            },
          ),
          const SizedBox(height: 8),

          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _submitError!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Submit Request',
            isLoading: _submitting,
            onPressed: _submit,
          ),
        ]),
      ),
    );
  }
}

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ReviewCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  String _label(String key) {
    const map = {
      'full_name':     'Full Name',
      'phone':         'Phone',
      'date_of_birth': 'Date of Birth',
      'gender':        'Gender',
    };
    return map[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final patient     = request['patient']      as Map<String, dynamic>?;
    final requestedBy = request['requested_by'] as Map<String, dynamic>?;
    final field       = request['field_name']   as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Expanded(
            child: Text(
              patient?['full_name'] as String? ?? 'Patient #${request['patient_id']}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Pending',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E)),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // Change details
        _Row(label: 'Field',     value: _label(field)),
        _Row(label: 'Old value', value: request['old_value'] as String? ?? '—'),
        _Row(label: 'New value', value: request['new_value'] as String? ?? '—'),
        _Row(label: 'Requested by',
            value: requestedBy?['name'] as String? ?? '—'),
        _Row(label: 'Reason',    value: request['reason']    as String? ?? '—'),
        const SizedBox(height: 14),

        // Action buttons
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onApprove,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ]),
    );
  }
}
