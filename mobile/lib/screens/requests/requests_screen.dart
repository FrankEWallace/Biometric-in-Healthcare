import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/patient_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_snackbar.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _service = PatientService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _service.getPendingEditRequests(token: _token);
      if (mounted) setState(() { _requests = list; _loading = false; });
    } on PatientException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _review(int id, bool approve) async {
    try {
      await _service.reviewEditRequest(
          token: _token, editRequestId: id, approve: approve);
      await _load();
      if (mounted) {
        showStatusSnackbar(context,
            message: approve ? 'Request approved.' : 'Request rejected.',
            status: approve ? SnackStatus.success : SnackStatus.error);
      }
    } on PatientException catch (e) {
      if (mounted) {
        showStatusSnackbar(context, message: e.message, status: SnackStatus.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Edit Requests'),
            if (_requests.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_requests.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E)),
                ),
              ),
            ],
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _requests.isEmpty
                  ? _EmptyView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: cs.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _RequestCard(
                          request: _requests[i],
                          onApprove: () =>
                              _review(_requests[i]['id'] as int, true),
                          onReject: () =>
                              _review(_requests[i]['id'] as int, false),
                        ),
                      ),
                    ),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  static const _fieldLabels = {
    'full_name':     'Full Name',
    'phone':         'Phone',
    'date_of_birth': 'Date of Birth',
    'gender':        'Gender',
  };

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final patient     = request['patient']      as Map<String, dynamic>?;
    final requestedBy = request['requested_by'] as Map<String, dynamic>?;
    final field       = request['field_name']   as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  patient?['full_name'] as String? ??
                      'Patient #${request['patient_id']}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
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
            ],
          ),
          const SizedBox(height: 12),

          _DataRow(label: 'Field',
              value: _fieldLabels[field] ?? field),
          _DataRow(label: 'Old value',
              value: request['old_value'] as String? ?? '—'),
          _DataRow(label: 'New value',
              value: request['new_value'] as String? ?? '—'),
          _DataRow(label: 'Requested by',
              value: requestedBy?['name'] as String? ?? '—'),
          _DataRow(label: 'Reason',
              value: request['reason'] as String? ?? '—'),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.cancel_rounded, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

// ── Empty / error ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_rounded, size: 56, color: AppColors.success),
        const SizedBox(height: 16),
        Text('All caught up!',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('No pending edit requests.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cancel_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}
