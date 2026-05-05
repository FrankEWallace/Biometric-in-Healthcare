import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'edit_request_screen.dart';
import 'patient_registration_screen.dart';
import 'staff_management_screen.dart';
import 'verification_screen.dart';
import 'login_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _locationService = LocationService();
  final _networkService  = NetworkService();

  bool? _withinRange;
  bool? _onHospitalWifi;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() {
      _withinRange    = null;
      _onHospitalWifi = null;
    });
    final results = await Future.wait([
      _locationService.isWithinHospitalRange(),
      _networkService.isConnectedToHospitalWifi(),
    ]);
    if (mounted) {
      setState(() {
        _withinRange    = results[0];
        _onHospitalWifi = results[1];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_withinRange == null || _onHospitalWifi == null) {
      return const _CheckingScreen();
    }
    if (_withinRange == false) {
      return _GeofenceBlockedScreen(onRetry: _runChecks);
    }
    return _DashboardBody(
      actionsEnabled: _onHospitalWifi!,
      onRetryWifi: _runChecks,
      onLogout: () => _confirmLogout(context),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of the system?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(90, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checking screen
// ─────────────────────────────────────────────────────────────────────────────

class _CheckingScreen extends StatelessWidget {
  const _CheckingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 20),
            Text(
              'Verifying access…',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Geofence blocked screen
// ─────────────────────────────────────────────────────────────────────────────

class _GeofenceBlockedScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _GeofenceBlockedScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off_rounded, size: 46, color: AppColors.error),
              ),
              const SizedBox(height: 24),
              const Text(
                'Access Restricted',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Access is restricted to hospital premises.\nPlease move within 200 m of the hospital and ensure location services are enabled.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 36),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.button,
                ),
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard body — role-based shell with bottom navigation
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatefulWidget {
  final bool actionsEnabled;
  final VoidCallback onRetryWifi;
  final VoidCallback onLogout;

  const _DashboardBody({
    required this.actionsEnabled,
    required this.onRetryWifi,
    required this.onLogout,
  });

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  int _selectedIndex = 0;

  List<_NavItem> _navItems(User user) {
    if (user.isNurse) {
      return const [
        _NavItem(icon: Icons.home_rounded,              label: 'Home'),
        _NavItem(icon: Icons.person_add_alt_1_rounded,  label: 'Register'),
        _NavItem(icon: Icons.fingerprint,               label: 'Verify'),
        _NavItem(icon: Icons.account_circle_rounded,    label: 'Profile'),
      ];
    }
    if (user.isDoctor) {
      return const [
        _NavItem(icon: Icons.home_rounded,              label: 'Home'),
        _NavItem(icon: Icons.people_rounded,            label: 'Patients'),
        _NavItem(icon: Icons.account_circle_rounded,    label: 'Profile'),
      ];
    }
    if (user.isSuperAdmin) {
      return const [
        _NavItem(icon: Icons.home_rounded,              label: 'Home'),
        _NavItem(icon: Icons.local_hospital_rounded,    label: 'Hospitals'),
        _NavItem(icon: Icons.account_circle_rounded,    label: 'Profile'),
      ];
    }
    // admin
    return const [
      _NavItem(icon: Icons.home_rounded,              label: 'Home'),
      _NavItem(icon: Icons.rate_review_rounded,       label: 'Requests'),
      _NavItem(icon: Icons.people_rounded,            label: 'Staff'),
      _NavItem(icon: Icons.account_circle_rounded,    label: 'Profile'),
    ];
  }

  Future<void> _onTabSelected(User user, int index) async {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    // Profile tab is last in all roles — handled inline
    final items = _navItems(user);
    if (index == items.length - 1) {
      setState(() => _selectedIndex = index);
      return;
    }

    // Secondary action tabs → push full screen, keep index on 0 when back
    setState(() => _selectedIndex = index);
    Widget? screen;

    if (user.isNurse) {
      if (index == 1) screen = const PatientRegistrationScreen();
      if (index == 2) screen = const VerificationScreen();
    } else if (user.isDoctor) {
      // patients tab is inline, no push needed
    } else if (user.isSuperAdmin) {
      // hospitals tab is inline, no push needed
    } else {
      // admin
      if (index == 1) screen = const EditRequestScreen(reviewMode: true);
      if (index == 2) screen = const StaffManagementScreen();
    }

    if (screen != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
      if (mounted) setState(() => _selectedIndex = 0);
    }
  }

  Widget _homeBody(User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeCard(user: user, onHospitalWifi: widget.actionsEnabled),
          const SizedBox(height: 12),
          if (!widget.actionsEnabled) ...[
            _WifiBanner(onRetry: widget.onRetryWifi),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          if (user.isNurse)
            _NurseDashboard(actionsEnabled: widget.actionsEnabled)
          else if (user.isDoctor)
            _DoctorDashboard(actionsEnabled: widget.actionsEnabled)
          else if (user.isSuperAdmin)
            _SuperAdminDashboard(actionsEnabled: widget.actionsEnabled)
          else
            _AdminDashboard(actionsEnabled: widget.actionsEnabled),
        ],
      ),
    );
  }

  Widget _currentBody(User user) {
    final items = _navItems(user);
    final isProfile = _selectedIndex == items.length - 1;
    if (isProfile) return _ProfileTab(user: user, onLogout: widget.onLogout);

    // Doctor patients tab (inline)
    if (user.isDoctor && _selectedIndex == 1) {
      return _PatientsTab(actionsEnabled: widget.actionsEnabled);
    }
    // Super admin hospitals tab (inline)
    if (user.isSuperAdmin && _selectedIndex == 1) {
      return _HospitalsTab(actionsEnabled: widget.actionsEnabled);
    }

    return _homeBody(user);
  }

  String _appBarTitle(User user) {
    final items = _navItems(user);
    if (_selectedIndex >= items.length) return 'Dashboard';
    return items[_selectedIndex].label;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();

    final items = _navItems(user);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_appBarTitle(user)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: SafeArea(child: _currentBody(user)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => _onTabSelected(user, i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: items
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final User user;
  final VoidCallback onLogout;
  const _ProfileTab({required this.user, required this.onLogout});

  String get _roleLabel => switch (user.role) {
    'super_admin' => 'Super Admin',
    'admin'       => 'Administrator',
    'doctor'      => 'Doctor',
    _             => 'Nurse',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_roleLabel, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(user.email, style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                _ProfileRow(icon: Icons.badge_outlined,    label: 'Role',     value: _roleLabel),
                const Divider(height: 1, indent: 56),
                _ProfileRow(icon: Icons.alternate_email_rounded, label: 'Username', value: user.username),
                const Divider(height: 1, indent: 56),
                _ProfileRow(icon: Icons.local_hospital_outlined, label: 'Hospital ID', value: user.hospitalId?.toString() ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              label: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ProfileRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patients tab (Doctor)
// ─────────────────────────────────────────────────────────────────────────────

class _PatientsTab extends StatelessWidget {
  final bool actionsEnabled;
  const _PatientsTab({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('Patient Search'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.card,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name or NIDA…',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search Patients'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      onPressed: actionsEnabled ? () {} : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Recent Verifications'),
          const SizedBox(height: 12),
          const _EmptyActivityCard(message: 'No recent verifications in your hospital'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hospitals tab (Super Admin)
// ─────────────────────────────────────────────────────────────────────────────

class _HospitalsTab extends StatelessWidget {
  final bool actionsEnabled;
  const _HospitalsTab({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('All Hospitals'),
          SizedBox(height: 12),
          _EmptyActivityCard(message: 'Hospital list coming soon'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nurse Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _NurseDashboard extends StatelessWidget {
  final bool actionsEnabled;
  const _NurseDashboard({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Today\'s Activity'),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(label: 'Registered',    value: '—', icon: Icons.how_to_reg_rounded,      color: AppColors.primary),
            const SizedBox(width: 10),
            _StatCard(label: 'Verified',      value: '—', icon: Icons.verified_user_rounded,    color: const Color(0xFF0D7C66)),
            const SizedBox(width: 10),
            _StatCard(label: 'Edit Requests', value: '—', icon: Icons.pending_actions_rounded,  color: AppColors.warning),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Quick Actions'),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Register Patient',
          subtitle: 'Enroll a new patient with fingerprint',
          color: AppColors.primary,
          enabled: actionsEnabled,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientRegistrationScreen())),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.fingerprint,
          title: 'Verify Patient',
          subtitle: 'Identify a patient by fingerprint scan',
          color: const Color(0xFF0D7C66),
          enabled: actionsEnabled,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen())),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.edit_note_rounded,
          title: 'Submit Edit Request',
          subtitle: 'Request a demographic change for a patient',
          color: AppColors.warning,
          enabled: actionsEnabled,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Edit request screen coming soon')),
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionHeader('My Recent Verifications'),
        const SizedBox(height: 12),
        const _EmptyActivityCard(message: 'No recent verifications'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Dashboard (admin + super_admin emergency mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _AdminDashboard extends StatelessWidget {
  final bool actionsEnabled;
  const _AdminDashboard({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Hospital Stats'),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(label: 'Patients',   value: '—', icon: Icons.people_rounded,           color: AppColors.primary),
            const SizedBox(width: 10),
            _StatCard(label: 'Enrolled',   value: '—', icon: Icons.fingerprint,               color: const Color(0xFF7C3AED)),
            const SizedBox(width: 10),
            _StatCard(label: 'Pending',    value: '—', icon: Icons.rate_review_rounded,       color: AppColors.warning),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Quick Actions'),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.fingerprint,
          title: 'Emergency Verification',
          subtitle: 'Verify a patient by fingerprint scan',
          color: const Color(0xFF0D7C66),
          enabled: actionsEnabled,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen())),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.rate_review_rounded,
          title: 'Review Edit Requests',
          subtitle: 'Approve or reject pending demographic changes',
          color: AppColors.primary,
          enabled: actionsEnabled,
          badge: '3',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const EditRequestScreen(reviewMode: true)),
          ),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.people_rounded,
          title: 'Staff Management',
          subtitle: 'View and manage hospital staff accounts',
          color: AppColors.textSecondary,
          enabled: actionsEnabled,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const StaffManagementScreen()),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Doctor Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _DoctorDashboard extends StatelessWidget {
  final bool actionsEnabled;
  const _DoctorDashboard({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Hospital Today'),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(label: 'Verifications', value: '—', icon: Icons.verified_user_rounded, color: const Color(0xFF0D7C66)),
            const SizedBox(width: 10),
            _StatCard(label: 'Patients',      value: '—', icon: Icons.people_rounded,        color: AppColors.primary),
            const SizedBox(width: 10),
            _StatCard(label: 'Match Rate',    value: '—%', icon: Icons.bar_chart_rounded,    color: const Color(0xFF7C3AED)),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Patient Lookup'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name or NIDA…',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (val) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Searching for "$val"…')),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search Patients'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: actionsEnabled ? () {} : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Recent Verifications'),
        const SizedBox(height: 12),
        const _EmptyActivityCard(message: 'No recent verifications in your hospital'),
        const SizedBox(height: 16),
        _InfoCard(
          icon: Icons.health_and_safety_rounded,
          message: 'EHR and insurance information is available after a successful fingerprint verification on this device.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Super Admin Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _SuperAdminDashboard extends StatelessWidget {
  final bool actionsEnabled;
  const _SuperAdminDashboard({required this.actionsEnabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('System Overview'),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(label: 'Hospitals', value: '—', icon: Icons.local_hospital_rounded,   color: const Color(0xFF7C3AED)),
            const SizedBox(width: 10),
            _StatCard(label: 'Patients',  value: '—', icon: Icons.people_rounded,           color: AppColors.primary),
            const SizedBox(width: 10),
            _StatCard(label: 'Today',     value: '—', icon: Icons.verified_user_rounded,    color: const Color(0xFF0D7C66)),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF7C3AED), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full Management Access', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2),
                        Text('Use the web dashboard for cross-hospital management', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _SuperAdminLink(icon: Icons.bar_chart_rounded,         label: 'Hospital Health Overview'),
              _SuperAdminLink(icon: Icons.rate_review_rounded,       label: 'All Edit Requests'),
              _SuperAdminLink(icon: Icons.people_rounded,            label: 'System-wide Staff Management'),
              _SuperAdminLink(icon: Icons.shield_rounded,            label: 'Full Audit Log'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuperAdminLink extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SuperAdminLink({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const Spacer(),
          const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.textHint),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  final User user;
  final bool onHospitalWifi;
  const _WelcomeCard({required this.user, required this.onHospitalWifi});

  String get _roleLabel => switch (user.role) {
    'super_admin' => 'Super Admin',
    'admin'       => 'Administrator',
    'doctor'      => 'Doctor',
    _             => 'Nurse',
  };

  Color get _roleAccent => switch (user.role) {
    'super_admin' => const Color(0xFFE11D48),
    'admin'       => const Color(0xFFF59E0B),
    'doctor'      => const Color(0xFF0EA5E9),
    _             => const Color(0xFF10B981),
  };

  String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.elevated,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_timeOfDay()},',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  user.name,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _roleAccent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _roleAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined, size: 12, color: _roleAccent),
                          const SizedBox(width: 5),
                          Text(_roleLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: onHospitalWifi
                            ? AppColors.success.withValues(alpha: 0.25)
                            : AppColors.error.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 7,
                              color: onHospitalWifi ? AppColors.success : const Color(0xFFFF8A80)),
                          const SizedBox(width: 5),
                          Text(
                            onHospitalWifi ? 'Hospital Network' : 'Off Network',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _WifiBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _WifiBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF92400E), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Connect to hospital network to perform actions',
              style: TextStyle(fontSize: 13, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: const Icon(Icons.refresh_rounded, color: Color(0xFF92400E), size: 20),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final String? badge;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : AppColors.textHint;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? AppShadows.card : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            splashColor: color.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: c, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (badge != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  Icon(Icons.chevron_right_rounded, color: c, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _InfoCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActivityCard extends StatelessWidget {
  final String message;
  const _EmptyActivityCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, size: 32, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
