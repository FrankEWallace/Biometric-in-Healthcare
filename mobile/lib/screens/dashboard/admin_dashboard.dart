import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/patient_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _staffSvc   = StaffService();
  final _patientSvc = PatientService();

  bool _loading = true;
  int  _totalStaff    = 0;
  int  _activeStaff   = 0;
  int  _pendingReqs   = 0;

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
      ]);
      final staff    = results[0] as List<dynamic>;
      final requests = results[1] as List<dynamic>;
      if (mounted) {
        setState(() {
          _totalStaff  = staff.length;
          _activeStaff = staff.where((s) => (s as Map)['is_active'] == true).length;
          _pendingReqs = requests.length;
          _loading     = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    final cs   = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: RefreshIndicator(
        onRefresh: _load,
        color: cs.primary,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good ${_greeting()},',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white70)),
                  Text(user.name,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ],
              ),
              centerTitle: false,
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : 'A',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
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

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
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
