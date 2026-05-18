import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/visit.dart';
import '../../providers/auth_provider.dart';
import '../../services/patient_service.dart';
import '../../services/staff_service.dart';
import '../../services/visit_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';
import '../clerk/visit_detail_screen.dart';
import '../profile/profile_screen.dart';
import 'supervisor_override_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _staffSvc   = StaffService();
  final _patientSvc = PatientService();
  final _visitSvc   = VisitService();

  bool _loading = true;
  int  _totalStaff    = 0;
  int  _activeStaff   = 0;
  int  _pendingReqs   = 0;
  List<VisitModel> _activeVisits  = [];
  int  _pendingOverrides = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _staffSvc.getStaff(token: _token),
        _patientSvc.getPendingEditRequests(token: _token),
        _visitSvc.getQueue(token: _token),
        _visitSvc.getPendingOverrides(token: _token),
      ]);
      final staff     = results[0] as List<dynamic>;
      final requests  = results[1] as List<dynamic>;
      final visits    = results[2] as List<VisitModel>;
      final overrides = results[3] as List<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          _totalStaff       = staff.length;
          _activeStaff      = staff.where((s) => (s as Map)['is_active'] == true).length;
          _pendingReqs      = requests.length;
          _activeVisits     = visits;
          _pendingOverrides = overrides.length;
          _loading          = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    final cs   = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              floating: true,
              snap: true,
              forceElevated: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good ${_greeting()},',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurfaceVariant)),
                  Text(user.name,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ],
              ),
              centerTitle: false,
              actions: [
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : 'A',
                        style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
              bottom: TabBar(
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: cs.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.monitor_heart_rounded), text: 'Live'),
                  Tab(icon: Icon(Icons.history_rounded), text: 'History'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              // ── Tab 0: Live ──────────────────────────────────────────
              RefreshIndicator(
                onRefresh: _load,
                color: cs.primary,
                child: CustomScrollView(
                  slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _roleLabel(user.role),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stat cards 2×2
                    _loading
                        ? _StatSkeleton()
                        : GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.35,
                            children: [
                              StatCard(
                                icon: Icons.group_rounded,
                                label: 'Total Staff',
                                value: '$_totalStaff',
                                subtitle: 'All registered users',
                              ),
                              StatCard(
                                icon: Icons.check_circle_rounded,
                                label: 'Active Staff',
                                value: '$_activeStaff',
                                subtitle: 'Currently enabled',
                                iconColor: AppColors.success,
                                iconBg: AppColors.successLight,
                              ),
                              StatCard(
                                icon: Icons.inbox_rounded,
                                label: 'Pending Requests',
                                value: '$_pendingReqs',
                                subtitle: 'Awaiting review',
                                iconColor: _pendingReqs > 0
                                    ? AppColors.warning
                                    : null,
                                iconBg: _pendingReqs > 0
                                    ? AppColors.warningLight
                                    : null,
                              ),
                              StatCard(
                                icon: Icons.people_alt_rounded,
                                label: 'Inactive Staff',
                                value: '${_totalStaff - _activeStaff}',
                                subtitle: 'Deactivated accounts',
                                iconColor: AppColors.error,
                                iconBg: AppColors.errorLight,
                              ),
                            ],
                          ),

                    const SizedBox(height: 24),

                    // Section header
                    Text('Quick Actions',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),

                    // Quick action cards
                    Row(
                      children: [
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.fingerprint,
                            label: 'Verify Patient',
                            color: AppColors.primary,
                            onTap: () => Navigator.pushNamed(context, '/verify'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Register Patient',
                            color: AppColors.success,
                            onTap: () => Navigator.pushNamed(context, '/register'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _QuickAction(
                      icon: Icons.admin_panel_settings_rounded,
                      label: 'Override Requests${_pendingOverrides > 0 ? ' ($_pendingOverrides pending)' : ''}',
                      color: _pendingOverrides > 0
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SupervisorOverrideScreen(),
                          ),
                        );
                        _load();
                      },
                    ),

                    const SizedBox(height: 24),

                    // Live visit feed
                    Text('Live Patient Journey',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${_activeVisits.length} active visit${_activeVisits.length == 1 ? '' : 's'} today',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    if (_activeVisits.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outline),
                        ),
                        child: const Center(
                          child: Text('No active visits right now',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        ),
                      )
                    else
                      ...List.generate(_activeVisits.length, (i) {
                        final visit = _activeVisits[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LiveVisitTile(
                            visit: visit,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      VisitDetailScreen(visitId: visit.id),
                                ),
                              );
                              _load();
                            },
                          ),
                        );
                      }),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
                ),
              ),

              // ── Tab 1: History ───────────────────────────────────────
              _HistoryTab(token: _token),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':       return 'Hospital Admin';
      case 'super_admin': return 'Super Admin';
      case 'doctor':      return 'Doctor';
      default:            return 'Nurse';
    }
  }
}

// ── Live visit tile ───────────────────────────────────────────────────────────

class _LiveVisitTile extends StatelessWidget {
  final VisitModel visit;
  final VoidCallback onTap;

  const _LiveVisitTile({required this.visit, required this.onTap});

  String _currentStage() {
    const order = [
      'clerk_checkin', 'triage', 'consultation',
      'laboratory', 'pharmacy', 'clerk_checkout',
    ];
    final pending = order.where((s) {
      final stage = visit.stageByName(s);
      return stage != null && stage.isPending;
    });
    if (pending.isEmpty) return 'Complete';
    return switch (pending.first) {
      'clerk_checkin'  => 'Check-in',
      'triage'         => 'Triage',
      'consultation'   => 'Consultation',
      'laboratory'     => 'Laboratory',
      'pharmacy'       => 'Pharmacy',
      'clerk_checkout' => 'Checkout',
      _                => pending.first,
    };
  }

  String _waitTime() {
    try {
      final opened = DateTime.parse(visit.openedAt).toLocal();
      final diff   = DateTime.now().difference(opened);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final completedCnt = visit.completedStages.length;
    const totalStages  = 6;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.patient?.fullName ?? 'Patient #${visit.patientId}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _currentStage(),
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$completedCnt/$totalStages stages',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: completedCnt / totalStages,
                      backgroundColor: cs.outlineVariant,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.success),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _waitTime(),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loader ───────────────────────────────────────────────────────────

class _StatSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: List.generate(4, (_) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      )),
    );
  }
}

// ── Quick action card ─────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── History tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  final String token;
  const _HistoryTab({required this.token});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab>
    with AutomaticKeepAliveClientMixin {
  final _service = VisitService();

  DateTime _selectedDate = DateTime.now();
  List<VisitModel> _visits = [];
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final visits = await _service.getVisitHistory(
          token: widget.token, date: dateStr);
      if (mounted) setState(() { _visits = visits; _loading = false; });
    } on VisitException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Visits on ${_formatDate(_selectedDate)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: _pickDate,
                child: const Text('Change date'),
              ),
            ],
          ),
        ),
        Expanded(
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
                  : _visits.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_rounded,
                                  size: 56,
                                  color: cs.onSurfaceVariant.withAlpha(100)),
                              const SizedBox(height: 12),
                              Text(
                                'No closed visits on ${_formatDate(_selectedDate)}',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _visits.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _HistoryVisitTile(
                              visit: _visits[i],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VisitDetailScreen(
                                      visitId: _visits[i].id),
                                ),
                              ),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _HistoryVisitTile extends StatelessWidget {
  final VisitModel visit;
  final VoidCallback onTap;

  const _HistoryVisitTile({required this.visit, required this.onTap});

  String _time(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.patient?.fullName ?? 'Patient #${visit.patientId}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    visit.patient?.displayId ?? '',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    visit.visitTypeLabel,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_time(visit.openedAt)} → ${_time(visit.closedAt ?? '')}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
