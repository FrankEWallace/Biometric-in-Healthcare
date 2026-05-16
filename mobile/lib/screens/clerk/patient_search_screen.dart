import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/patient.dart';
import '../../providers/auth_provider.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import 'clerk_scan_screen.dart';

class PatientSearchScreen extends StatefulWidget {
  const PatientSearchScreen({super.key});

  @override
  State<PatientSearchScreen> createState() => _PatientSearchScreenState();
}

class _PatientSearchScreenState extends State<PatientSearchScreen> {
  final _controller = TextEditingController();
  final _service    = VisitService();

  List<PatientModel> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() { _results = []; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String q) async {
    final token = context.read<AuthProvider>().user?.token ?? '';
    setState(() { _loading = true; _error = null; });
    try {
      final results = await _service.searchPatients(token: token, query: q);
      if (mounted) setState(() { _results = results; _loading = false; });
    } on VisitException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _selectPatient(PatientModel patient) {
    if (patient.hasOpenVisit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${patient.fullName} already has an open visit.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (!patient.isEnrolled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${patient.fullName} has no enrolled fingerprint.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClerkScanScreen(patient: patient)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Find Patient')),
      body: Column(
        children: [
          // Search bar
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: TextField(
              controller: _controller,
              onChanged: _onSearch,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by ID, name, or phone…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _controller.clear();
                              setState(() { _results = []; _error = null; });
                            },
                          )
                        : null,
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),

          // Empty hint
          if (_results.isEmpty && !_loading && _error == null && _controller.text.length < 2)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_search_rounded, size: 56,
                        color: cs.onSurfaceVariant.withAlpha(100)),
                    const SizedBox(height: 12),
                    Text('Type at least 2 characters to search',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  ],
                ),
              ),
            ),

          // No results
          if (_results.isEmpty && !_loading && _controller.text.length >= 2 && _error == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded, size: 56,
                        color: cs.onSurfaceVariant.withAlpha(100)),
                    const SizedBox(height: 12),
                    Text('No patients found', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),

          // Results list
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PatientTile(
                  patient: _results[i],
                  onTap: () => _selectPatient(_results[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback onTap;

  const _PatientTile({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: patient.hasOpenVisit
                ? AppColors.warning.withAlpha(100)
                : cs.outline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: patient.hasOpenVisit
                    ? AppColors.warningLight
                    : AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                patient.hasOpenVisit
                    ? Icons.event_busy_rounded
                    : Icons.person_rounded,
                color: patient.hasOpenVisit
                    ? AppColors.warning
                    : AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(patient.displayId,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                  if (patient.phone != null) ...[
                    const SizedBox(height: 2),
                    Text(patient.phone!,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (patient.hasOpenVisit)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Active Visit',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              )
            else if (!patient.isEnrolled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Not Enrolled',
                    style: TextStyle(
                        color: AppColors.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              )
            else
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
