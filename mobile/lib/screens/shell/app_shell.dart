import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../screens/dashboard/admin_dashboard.dart';
import '../../screens/dashboard/nurse_dashboard.dart';
import '../../screens/dashboard/super_admin_dashboard.dart';
import '../../screens/staff/staff_screen.dart';
import '../../screens/requests/requests_screen.dart';
import '../../screens/emergency/emergency_registration_screen.dart';
import '../../screens/verification_screen.dart';
import '../../screens/verify/hand_verification_screen.dart';
import '../../screens/patient_registration_screen.dart';
import '../../screens/face/face_verification_screen.dart';
import '../../screens/clerk/clerk_dashboard.dart';
import '../../screens/clerk/clerk_history_screen.dart';
import '../../screens/clerk/clerk_summary_screen.dart';
import '../../screens/visit/stage_queue_screen.dart';
import '../../services/hospital_service.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../theme/app_theme.dart';

// ── Tab descriptor ────────────────────────────────────────────────────────────

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;

  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.screen,
  });
}

// ── Geofence wrapper for clinical screens ─────────────────────────────────────

class GeoGatedScreen extends StatefulWidget {
  final Widget child;
  const GeoGatedScreen({super.key, required this.child});

  @override
  State<GeoGatedScreen> createState() => _GeoGatedScreenState();
}

class _GeoGatedScreenState extends State<GeoGatedScreen> {
  final _loc = LocationService();
  final _net = NetworkService();
  final _hospitalService = HospitalService();

  bool? _inRange;
  bool? _onWifi;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() { _inRange = null; _onWifi = null; });

    final user = context.read<AuthProvider>().user;
    String? expectedSsid;
    if (user?.hospitalId != null) {
      try {
        final hospital = await _hospitalService.getHospital(
          token: user!.token,
          hospitalId: user.hospitalId!,
        );
        expectedSsid = hospital['wifi_ssid'] as String?;
      } catch (_) {
        expectedSsid = null;
      }
    }

    final results = await Future.wait([
      _loc.isWithinHospitalRange(),
      _net.isConnectedToHospitalWifi(expectedSsid),
    ]);
    if (mounted) {
      setState(() { _inRange = results[0]; _onWifi = results[1]; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_inRange == null || _onWifi == null) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text('Verifying access…',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ]),
        ),
      );
    }

    if (_inRange == false) {
      return _BlockScreen(
        icon: Icons.location_off_rounded,
        iconColor: AppColors.error,
        iconBg: AppColors.errorLight,
        title: 'Outside Hospital Range',
        body: 'This feature is only available within 200 m of the hospital.',
        onRetry: _check,
      );
    }

    if (_onWifi == false) {
      return _BlockScreen(
        icon: Icons.wifi_off_rounded,
        iconColor: AppColors.warning,
        iconBg: AppColors.warningLight,
        title: 'Hospital Wi-Fi Required',
        body: 'Connect to the hospital Wi-Fi network to use this feature.',
        onRetry: _check,
      );
    }

    return widget.child;
  }
}

class _BlockScreen extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String body;
  final VoidCallback onRetry;

  const _BlockScreen({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.body,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: iconColor),
              ),
              const SizedBox(height: 24),
              Text(title,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body,
                  style: TextStyle(
                      fontSize: 14, color: cs.onSurfaceVariant, height: 1.6),
                  textAlign: TextAlign.center),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Try Again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── App Shell ─────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<_Tab> _tabsForRole(String role) {
    switch (role) {
      case 'admin':
        return const [
          _Tab(label: 'Dashboard', icon: Icons.dashboard_outlined,  activeIcon: Icons.dashboard_rounded,  screen: AdminDashboard()),
          _Tab(label: 'Staff',     icon: Icons.group_outlined,       activeIcon: Icons.group_rounded,       screen: StaffScreen()),
          _Tab(label: 'Requests',  icon: Icons.inbox_outlined,       activeIcon: Icons.inbox_rounded,       screen: RequestsScreen()),
          _Tab(label: 'Emergency', icon: Icons.emergency_outlined,   activeIcon: Icons.emergency_rounded,   screen: EmergencyRegistrationScreen()),
        ];
      case 'super_admin':
        return const [
          _Tab(label: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, screen: SuperAdminDashboard()),
          _Tab(label: 'Staff',     icon: Icons.group_outlined,      activeIcon: Icons.group_rounded,      screen: StaffScreen()),
        ];
      case 'clerk':
        return const [
          _Tab(label: 'Dashboard', icon: Icons.dashboard_outlined,  activeIcon: Icons.dashboard_rounded,  screen: ClerkSummaryScreen()),
          _Tab(label: 'Queue',     icon: Icons.inbox_outlined,       activeIcon: Icons.inbox_rounded,       screen: GeoGatedScreen(child: ClerkDashboard())),
          _Tab(label: 'History',   icon: Icons.history_rounded,      activeIcon: Icons.history_rounded,     screen: ClerkHistoryScreen()),
        ];
      case 'nurse':
        return [
          const _Tab(label: 'Dashboard',   icon: Icons.dashboard_outlined,       activeIcon: Icons.dashboard_rounded,        screen: NurseDashboard()),
          _Tab(label: 'Queue',             icon: Icons.queue_rounded,             activeIcon: Icons.queue_rounded,            screen: const GeoGatedScreen(child: StageQueueScreen())),
          _Tab(label: 'Fingerprint',       icon: Icons.fingerprint,               activeIcon: Icons.fingerprint,              screen: const GeoGatedScreen(child: HandVerificationScreen())),
          _Tab(label: 'Face ID',           icon: Icons.face_outlined,             activeIcon: Icons.face_rounded,             screen: const GeoGatedScreen(child: FaceVerificationScreen())),
          _Tab(label: 'Register',          icon: Icons.person_add_alt_1_outlined, activeIcon: Icons.person_add_alt_1_rounded, screen: const GeoGatedScreen(child: PatientRegistrationScreen())),
        ];
      case 'doctor':
      case 'lab_technician':
      case 'pharmacist':
        return [
          const _Tab(label: 'Dashboard',   icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded,  screen: NurseDashboard()),
          _Tab(label: 'Queue',             icon: Icons.queue_rounded,       activeIcon: Icons.queue_rounded,      screen: const GeoGatedScreen(child: StageQueueScreen())),
          _Tab(label: 'Fingerprint',       icon: Icons.fingerprint,         activeIcon: Icons.fingerprint,        screen: const GeoGatedScreen(child: VerificationScreen())),
          _Tab(label: 'Face ID',           icon: Icons.face_outlined,       activeIcon: Icons.face_rounded,       screen: const GeoGatedScreen(child: FaceVerificationScreen())),
        ];
      default:
        return [
          const _Tab(label: 'Dashboard', icon: Icons.dashboard_outlined,       activeIcon: Icons.dashboard_rounded,        screen: NurseDashboard()),
          _Tab(label: 'Queue',           icon: Icons.queue_rounded,             activeIcon: Icons.queue_rounded,            screen: const GeoGatedScreen(child: StageQueueScreen())),
          _Tab(label: 'Fingerprint',     icon: Icons.fingerprint,               activeIcon: Icons.fingerprint,              screen: const GeoGatedScreen(child: VerificationScreen())),
          _Tab(label: 'Face ID',         icon: Icons.face_outlined,             activeIcon: Icons.face_rounded,             screen: const GeoGatedScreen(child: FaceVerificationScreen())),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const SizedBox.shrink();
    }
    final tabs = _tabsForRole(user.role);
    final cs   = Theme.of(context).colorScheme;

    // Clamp index if role change shrinks tab count
    final safeIndex = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: tabs.length < 2 ? null : Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outline, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: safeIndex,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: tabs
              .map((t) => NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.activeIcon),
                    label: t.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
