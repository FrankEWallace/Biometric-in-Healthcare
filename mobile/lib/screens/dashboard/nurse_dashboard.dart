import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../screens/edit_request_screen.dart';
import '../../screens/shell/app_shell.dart';
import '../../screens/verification_screen.dart';
import '../../screens/patient_registration_screen.dart';
import '../../theme/app_theme.dart';

class NurseDashboard extends StatefulWidget {
  const NurseDashboard({super.key});

  @override
  State<NurseDashboard> createState() => _NurseDashboardState();
}

class _NurseDashboardState extends State<NurseDashboard> {
  final _loc = LocationService();
  final _net = NetworkService();

  bool? _inRange;
  bool? _onWifi;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() { _inRange = null; _onWifi = null; });
    final r = await Future.wait([
      _loc.isWithinHospitalRange(),
      _net.isConnectedToHospitalWifi(),
    ]);
    if (mounted) setState(() { _inRange = r[0]; _onWifi = r[1]; });
  }

  void _pushGated(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeoGatedScreen(child: screen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    final cs   = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good ${_greeting()},',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70)),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
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
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'N',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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
                      user.isDoctor ? 'Doctor' : 'Nurse',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Access status cards
                  Text('Access Status', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _StatusTile(
                        icon: Icons.location_on_rounded,
                        label: 'Location',
                        status: _inRange,
                        okText: 'Within range',
                        failText: 'Out of range',
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _StatusTile(
                        icon: Icons.wifi_rounded,
                        label: 'Wi-Fi',
                        status: _onWifi,
                        okText: 'Hospital Wi-Fi',
                        failText: 'Not connected',
                      )),
                    ],
                  ),
                  if (_inRange == false || _onWifi == false) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _check,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  Text('Actions', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.fingerprint,
                    title: 'Verify Patient',
                    subtitle: 'Match fingerprint to patient record',
                    color: AppColors.primary,
                    onTap: () => _pushGated(context, const VerificationScreen()),
                  ),
                  const SizedBox(height: 10),
                  _ActionCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Register Patient',
                    subtitle: 'Enroll a new patient with fingerprint',
                    color: AppColors.success,
                    onTap: () => _pushGated(context, const PatientRegistrationScreen()),
                  ),
                  const SizedBox(height: 10),
                  _ActionCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Request Record Edit',
                    subtitle: 'Submit a change for admin approval',
                    color: AppColors.warning,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditRequestScreen(reviewMode: false),
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
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

// ── Status tile ───────────────────────────────────────────────────────────────

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? status;
  final String okText;
  final String failText;

  const _StatusTile({
    required this.icon,
    required this.label,
    required this.status,
    required this.okText,
    required this.failText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, bg, text) = status == null
        ? (cs.onSurfaceVariant, cs.surface, 'Checking…')
        : status!
            ? (AppColors.success, AppColors.successLight, okText)
            : (AppColors.error, AppColors.errorLight, failText);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == null
              ? cs.outline
              : status!
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                Text(text,
                    style: TextStyle(
                        fontSize: 11, color: color.withValues(alpha: 0.8))),
              ],
            ),
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
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
