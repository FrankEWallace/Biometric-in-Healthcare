import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'home_dashboard.dart';

class ResultScreen extends StatefulWidget {
  final bool isSuccess;
  final String? patientName;
  final String? patientId;
  final bool isRegistration;

  /// Verification score 0–100 returned by the Python matching service.
  /// When provided it replaces the placeholder "Match: 97%".
  final double? score;

  /// The finger position that was matched (e.g. "right_index").
  final String? matchedFinger;

  /// How many verification attempts have been made for this patient.
  final int attemptCount;

  /// Maximum allowed attempts before escalating to alternative verification.
  final int maxAttempts;

  const ResultScreen({
    super.key,
    required this.isSuccess,
    this.patientName,
    this.patientId,
    this.isRegistration = false,
    this.score,
    this.matchedFinger,
    this.attemptCount = 0,
    this.maxAttempts  = 3,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _controller, curve: const Interval(0.3, 1.0)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isSuccess ? AppColors.success : AppColors.error;
    final bgColor = widget.isSuccess
        ? AppColors.success.withValues(alpha: 0.08)
        : AppColors.error.withValues(alpha: 0.08);
    final icon =
        widget.isSuccess ? Icons.check_circle : Icons.cancel;
    final headline = widget.isRegistration
        ? (widget.isSuccess
            ? 'Patient Registered!'
            : 'Registration Failed')
        : (widget.isSuccess ? 'Patient Verified' : 'No Match Found');
    final subtext = widget.isRegistration
        ? (widget.isSuccess
            ? 'Fingerprint saved successfully.'
            : 'Could not save fingerprint. Please try again.')
        : (widget.isSuccess
            ? 'Identity confirmed successfully.'
            : 'The fingerprint did not match any registered patient.');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Animated result icon
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => Transform.scale(
                  scale: _scaleAnim.value,
                  child: child,
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3), width: 3),
                  ),
                  child: Icon(icon, size: 64, color: color),
                ),
              ),
              const SizedBox(height: 24),

              FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtext,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    // Score ring — shown for successful verifications with a score
                    if (widget.isSuccess &&
                        !widget.isRegistration &&
                        widget.score != null) ...[
                      const SizedBox(height: 24),
                      _ScoreRing(
                        score: widget.score!,
                        animation: _fadeAnim,
                        color: color,
                      ),
                    ],
                  ],
                ),
              ),

              // Patient detail card (only on success)
              if (widget.isSuccess &&
                  widget.patientName != null) ...[
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patient Details',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.person,
                                  color: AppColors.primary, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.patientName!,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.patientId ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Verified',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppColors.divider),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.fingerprint,
                              label: widget.score != null
                                  ? 'Score: ${widget.score!.toStringAsFixed(1)}%'
                                  : 'Fingerprint OK',
                            ),
                            const SizedBox(width: 10),
                            if (widget.matchedFinger != null &&
                                widget.matchedFinger!.isNotEmpty)
                              _InfoChip(
                                icon: Icons.back_hand_outlined,
                                label: widget.matchedFinger!
                                    .replaceAll('_', ' '),
                              )
                            else
                              _InfoChip(
                                icon: Icons.access_time,
                                label: _currentTime(),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const Spacer(),

              PrimaryButton(
                label: 'Back to Dashboard',
                icon: Icons.home,
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const HomeDashboard()),
                  (route) => false,
                ),
              ),
              if (!widget.isSuccess && !widget.isRegistration) ...[
                const SizedBox(height: 12),
                if (widget.attemptCount < widget.maxAttempts)
                  SecondaryButton(
                    label: 'Try Again'
                        ' (${widget.maxAttempts - widget.attemptCount} left)',
                    icon: Icons.refresh,
                    onPressed: () => Navigator.pop(context),
                  )
                else
                  _AlternativeVerificationBanner(patientId: widget.patientId),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Animated score ring ────────────────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  final double score;
  final Animation<double> animation;
  final Color color;

  const _ScoreRing({
    required this.score,
    required this.animation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(
            painter: _ScoreRingPainter(
              score: score,
              progress: animation.value,
              color: color,
              trackColor: color.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(score * animation.value).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    'match',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Alternative verification banner (shown after max retries) ─────────────────

class _AlternativeVerificationBanner extends StatelessWidget {
  final String? patientId;

  const _AlternativeVerificationBanner({this.patientId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFB300), size: 18),
              SizedBox(width: 8),
              Text(
                'Maximum Attempts Reached',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7B5800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fingerprint could not be verified after 3 attempts.'
            '${patientId != null ? ' Patient: $patientId.' : ''}'
            ' Please use an alternative method:',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF7B5800),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          const _AltOption(
            icon: Icons.badge_outlined,
            label: 'Check NHIF/CHF card manually',
          ),
          const _AltOption(
            icon: Icons.supervised_user_circle_outlined,
            label: 'Request supervisor override',
          ),
          const _AltOption(
            icon: Icons.assignment_ind_outlined,
            label: 'Verify via National ID (NIDA)',
          ),
        ],
      ),
    );
  }
}

class _AltOption extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AltOption({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFFFFB300)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7B5800),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double score;
  final double progress;
  final Color color;
  final Color trackColor;

  _ScoreRingPainter({
    required this.score,
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2; // top

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Arc
    final sweepAngle = 2 * math.pi * (score / 100) * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.score != score || old.color != color;
}
