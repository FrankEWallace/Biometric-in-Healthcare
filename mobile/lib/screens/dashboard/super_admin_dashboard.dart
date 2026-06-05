import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../screens/hospital/hospital_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../services/hospital_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final _staffSvc    = StaffService();
  final _hospitalSvc = HospitalService();

  bool _loading = true;
  int _totalStaff     = 0;
  int _activeStaff    = 0;
  int _totalHospitals = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _token => context.read<AuthProvider>().user!.token;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final staffFuture    = _staffSvc.getStaff(token: _token);
      final hospitalFuture = _hospitalSvc.getHospitals(token: _token);
      final staff          = await staffFuture;
      final hospitals      = await hospitalFuture;
      if (mounted) {
        setState(() {
          _totalStaff     = staff.length;
          _activeStaff    = staff.where((s) => s['is_active'] == true).length;
          _totalHospitals = hospitals.length;
          _loading        = false;
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
                  Text('Super Admin',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant)),
                  Text(user.name,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
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
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : 'S',
                        style: TextStyle(
                            color: cs.onPrimaryContainer, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Super Admin',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text('Overview', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),

                    _loading
                        ? _Skeleton()
                        : GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.35,
                            children: [
                              StatCard(
                                icon: Icons.local_hospital_rounded,
                                label: 'Hospitals',
                                value: '$_totalHospitals',
                                subtitle: 'All registered',
                              ),
                              StatCard(
                                icon: Icons.group_rounded,
                                label: 'Total Staff',
                                value: '$_totalStaff',
                                subtitle: 'All hospitals',
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
                                icon: Icons.people_alt_rounded,
                                label: 'Inactive',
                                value: '${_totalStaff - _activeStaff}',
                                subtitle: 'Deactivated',
                                iconColor: AppColors.error,
                                iconBg: AppColors.errorLight,
                              ),
                            ],
                          ),

                    const SizedBox(height: 24),

                    Text('Hospitals', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HospitalScreen()),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outline),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_hospital_rounded,
                                  size: 20, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Manage Hospitals',
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text('Add, edit, and set GPS geofence per hospital',
                                      style: TextStyle(
                                          fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
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
}

class _Skeleton extends StatelessWidget {
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
        child: const Center(child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))),
      )),
    );
  }
}
