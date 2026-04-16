import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'home_dashboard.dart';

/// Displays Electronic Health Record (EHR) and insurance eligibility data
/// fetched from GoT-HoMIS after a successful fingerprint verification.
class EhrScreen extends StatelessWidget {
  final String patientName;
  final double score;
  final String? matchedFinger;
  final Map<String, dynamic>? ehr;
  final Map<String, dynamic>? insurance;

  const EhrScreen({
    super.key,
    required this.patientName,
    required this.score,
    this.matchedFinger,
    this.ehr,
    this.insurance,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Patient Record',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _VerifiedBanner(
            patientName: patientName,
            score: score,
            matchedFinger: matchedFinger,
          ),
          const SizedBox(height: 16),
          _EhrSection(ehr: ehr),
          const SizedBox(height: 16),
          _InsuranceSection(insurance: insurance),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Back to Dashboard',
            icon: Icons.home,
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeDashboard()),
              (route) => false,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Verified banner ────────────────────────────────────────────────────────────

class _VerifiedBanner extends StatelessWidget {
  final String patientName;
  final double score;
  final String? matchedFinger;

  const _VerifiedBanner({
    required this.patientName,
    required this.score,
    this.matchedFinger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user, color: AppColors.success, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patientName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Match ${score.toStringAsFixed(1)}%'
                  '${matchedFinger != null ? ' · ${matchedFinger!.replaceAll('_', ' ')}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Verified',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EHR section ────────────────────────────────────────────────────────────────

class _EhrSection extends StatelessWidget {
  final Map<String, dynamic>? ehr;

  const _EhrSection({this.ehr});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Electronic Health Record',
      icon: Icons.medical_information_outlined,
      iconColor: AppColors.primary,
      child: ehr == null
          ? const _UnavailableNote(
              message: 'GoT-HoMIS record unavailable. Verify patient manually.',
            )
          : Column(
              children: [
                _Row('Full Name',    _str(ehr, 'full_name')),
                _Row('Date of Birth', _str(ehr, 'date_of_birth')),
                _Row('Gender',       _str(ehr, 'gender')),
                _Row('Patient ID',   _str(ehr, 'patient_id')),
                _Row('Blood Type',   _str(ehr, 'blood_type')),
                _Row('Allergies',    _str(ehr, 'allergies')),
                _Row('Last Visit',   _str(ehr, 'last_visit_date')),
                _Row('Facility',     _str(ehr, 'registered_facility')),
              ],
            ),
    );
  }
}

// ── Insurance section ──────────────────────────────────────────────────────────

class _InsuranceSection extends StatelessWidget {
  final Map<String, dynamic>? insurance;

  const _InsuranceSection({this.insurance});

  @override
  Widget build(BuildContext context) {
    final eligible = insurance?['eligible'] as bool?;

    return _Card(
      title: 'Insurance Eligibility',
      icon: Icons.health_and_safety_outlined,
      iconColor: eligible == true ? AppColors.success : AppColors.textSecondary,
      child: insurance == null
          ? const _UnavailableNote(
              message: 'Insurance status unavailable. Check manually with NHIF/CHF.',
            )
          : Column(
              children: [
                _EligibilityBadge(eligible: eligible),
                const SizedBox(height: 12),
                _Row('Scheme',      _str(insurance, 'scheme')),
                _Row('Member No.',  _str(insurance, 'member_number')),
                _Row('Valid Until', _str(insurance, 'valid_until')),
                _Row('Card No.',    _str(insurance, 'card_number')),
                _Row('Benefit',     _str(insurance, 'benefit_package')),
              ],
            ),
    );
  }
}

class _EligibilityBadge extends StatelessWidget {
  final bool? eligible;

  const _EligibilityBadge({this.eligible});

  @override
  Widget build(BuildContext context) {
    if (eligible == null) return const SizedBox.shrink();

    final color = eligible! ? AppColors.success : AppColors.error;
    final bg    = eligible! ? AppColors.successLight : AppColors.errorLight;
    final label = eligible! ? 'Eligible' : 'Not Eligible';
    final icon  = eligible! ? Icons.check_circle_outline : Icons.cancel_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared primitives ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.divider, height: 20),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == '—') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  final String message;

  const _UnavailableNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

String _str(Map<String, dynamic>? map, String key) {
  if (map == null) return '—';
  final v = map[key];
  if (v == null || v.toString().isEmpty) return '—';
  return v.toString();
}
