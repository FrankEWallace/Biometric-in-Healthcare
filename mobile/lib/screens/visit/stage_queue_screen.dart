import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/visit.dart';
import '../../providers/auth_provider.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import 'stage_verify_screen.dart';

/// Queue screen for non-clerk roles.
/// Shows patients pending at the staff member's assigned stage.
class StageQueueScreen extends StatefulWidget {
  const StageQueueScreen({super.key});

  @override
  State<StageQueueScreen> createState() => _StageQueueScreenState();
}

class _StageQueueScreenState extends State<StageQueueScreen> {
  final _service = VisitService();

  List<VisitModel> _queue = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().user?.token ?? '';
    setState(() { _loading = true; _error = null; });
    try {
      final queue = await _service.getQueue(token: token);
      if (mounted) setState(() { _queue = queue; _loading = false; });
    } on VisitException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final user = context.read<AuthProvider>().user!;

    final stageLabel = switch (user.assignedStage) {
      'triage'         => 'Triage',
      'consultation'   => 'Consultation',
      'laboratory'     => 'Laboratory',
      'pharmacy'       => 'Pharmacy',
      _                => 'Queue',
    };

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(stageLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _queue.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.playlist_add_check_circle_rounded,
                                      size: 56,
                                      color: cs.onSurfaceVariant.withAlpha(100)),
                                  const SizedBox(height: 12),
                                  Text('No patients waiting',
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 15)),
                                  const SizedBox(height: 8),
                                  Text('Pull to refresh',
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _queue.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _QueueTile(
                          visit: _queue[i],
                          stageName: user.assignedStage ?? '',
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StageVerifyScreen(
                                  visit: _queue[i],
                                  stageName: user.assignedStage ?? '',
                                ),
                              ),
                            );
                            _load();
                          },
                        ),
                      ),
      ),
    );
  }
}

// ── Queue tile ────────────────────────────────────────────────────────────────

class _QueueTile extends StatelessWidget {
  final VisitModel visit;
  final String stageName;
  final VoidCallback onTap;

  const _QueueTile({
    required this.visit,
    required this.stageName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final patient = visit.patient;

    // How long since check-in
    final openedAt = DateTime.tryParse(visit.openedAt)?.toLocal();
    final waitMins = openedAt != null
        ? DateTime.now().difference(openedAt).inMinutes
        : 0;

    final waitColor = waitMins > 60
        ? AppColors.error
        : waitMins > 30
            ? AppColors.warning
            : AppColors.success;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient?.fullName ?? 'Patient #${visit.patientId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(patient?.displayId ?? '',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: waitColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${waitMins}m',
                      style: TextStyle(
                          color: waitColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(visit.visitTypeLabel,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
