import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'patient_registration_screen.dart';
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
        content: const Text(
            'Are you sure you want to sign out of the system?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(90, 42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
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

// ── Checking screen ───────────────────────────────────────────────────────────

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
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Geofence blocked screen ───────────────────────────────────────────────────

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
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off_rounded,
                    size: 46, color: AppColors.error),
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
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
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
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashboard body ────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final bool actionsEnabled;
  final VoidCallback onRetryWifi;
  final VoidCallback onLogout;

  const _DashboardBody({
    required this.actionsEnabled,
    required this.onRetryWifi,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: onLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Welcome card ────────────────────────────────────────────
              _WelcomeCard(
                userName: user?.name ?? 'Staff',
                userRole: user?.role ?? 'nurse',
                onHospitalWifi: actionsEnabled,
              ),
              const SizedBox(height: 12),

              // ── WiFi warning ─────────────────────────────────────────────
              if (!actionsEnabled) ...[
                _WifiBanner(onRetry: onRetryWifi),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),

              // ── Action cards ─────────────────────────────────────────────
              _ActionCard(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Register Patient',
                subtitle: 'Enroll a new patient with fingerprint',
                color: AppColors.primary,
                enabled: actionsEnabled,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PatientRegistrationScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.fingerprint,
                title: 'Verify Patient',
                subtitle: 'Identify patient by fingerprint scan',
                color: const Color(0xFF0D7C66),
                enabled: actionsEnabled,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VerificationScreen()),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                "Today's Activity",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),

              // ── Stats row ────────────────────────────────────────────────
              Row(
                children: [
                  _StatCard(
                    label: 'Registered',
                    value: '12',
                    icon: Icons.how_to_reg_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Verified',
                    value: '34',
                    icon: Icons.verified_user_rounded,
                    color: const Color(0xFF0D7C66),
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Pending',
                    value: '3',
                    icon: Icons.pending_actions_rounded,
                    color: AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Welcome card ──────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  final String userName;
  final String userRole;
  final bool onHospitalWifi;

  const _WelcomeCard({
    required this.userName,
    required this.userRole,
    required this.onHospitalWifi,
  });

  String get _roleLabel {
    switch (userRole.toLowerCase()) {
      case 'admin': return 'Administrator';
      case 'doctor': return 'Doctor';
      default: return 'Nurse';
    }
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Badge(
                      icon: Icons.badge_outlined,
                      label: _roleLabel,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    const SizedBox(width: 8),
                    _Badge(
                      icon: Icons.circle,
                      iconSize: 7,
                      label: onHospitalWifi
                          ? 'On Hospital Network'
                          : 'Off Network',
                      color: onHospitalWifi
                          ? AppColors.success.withValues(alpha: 0.25)
                          : AppColors.error.withValues(alpha: 0.3),
                      iconColor: onHospitalWifi
                          ? AppColors.success
                          : const Color(0xFFFF8A80),
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
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? iconColor;
  final double iconSize;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor,
    this.iconSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: iconSize,
              color: iconColor ?? Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── WiFi banner ───────────────────────────────────────────────────────────────

class _WifiBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _WifiBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: Color(0xFF92400E), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Connect to hospital network to continue',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: const Icon(Icons.refresh_rounded,
                color: Color(0xFF92400E), size: 20),
          ),
        ],
      ),
    );
  }
}

// ── Action card ───────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
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
            highlightColor: color.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
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
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
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

// ── Stat card ─────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
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
