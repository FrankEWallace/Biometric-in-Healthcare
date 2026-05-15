import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Oval face-framing guide with animated breathing border.
/// Drop this over a live camera preview to guide the user to center their face.
class FaceOverlay extends StatefulWidget {
  final bool isScanning;

  const FaceOverlay({super.key, this.isScanning = false});

  @override
  State<FaceOverlay> createState() => _FaceOverlayState();
}

class _FaceOverlayState extends State<FaceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Oval: 68% of screen width, 55% of height — fits most face sizes
        final ovalW = w * 0.68;
        final ovalH = h * 0.55;

        return Stack(
          alignment: Alignment.center,
          children: [
            // ── Frosted dark surround (everything outside the oval) ──────
            CustomPaint(
              size: Size(w, h),
              painter: _SurroundPainter(
                ovalW: ovalW,
                ovalH: ovalH,
                centerX: w / 2,
                centerY: h / 2,
              ),
            ),

            // ── Animated oval border ─────────────────────────────────────
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final borderColor = widget.isScanning
                    ? Color.lerp(
                        AppColors.primary,
                        AppColors.primaryLight,
                        _pulse.value,
                      )!
                    : AppColors.primary;

                return SizedBox(
                  width: ovalW,
                  height: ovalH,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.all(
                          Radius.elliptical(ovalW / 2, ovalH / 2)),
                      border: Border.all(
                        color: borderColor.withValues(
                            alpha: widget.isScanning
                                ? 0.6 + 0.4 * _pulse.value
                                : 0.7),
                        width: 2.5,
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── Ghost face icon ──────────────────────────────────────────
            Icon(
              Icons.face_outlined,
              size: ovalW * 0.45,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ],
        );
      },
    );
  }
}

// ── Dark surround painter ─────────────────────────────────────────────────────

class _SurroundPainter extends CustomPainter {
  final double ovalW;
  final double ovalH;
  final double centerX;
  final double centerY;

  const _SurroundPainter({
    required this.ovalW,
    required this.ovalH,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Full-screen path minus the oval cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: ovalW,
        height: ovalH,
      ));

    canvas.drawPath(path.shift(Offset.zero)
      ..fillType = PathFillType.evenOdd, paint);
  }

  @override
  bool shouldRepaint(_SurroundPainter old) =>
      old.ovalW != ovalW || old.ovalH != ovalH;
}
