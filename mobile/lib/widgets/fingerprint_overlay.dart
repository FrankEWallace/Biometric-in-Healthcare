import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Rectangular scanning frame with animated corner brackets and scan line.
///
/// [isScanning]    — activates scan animation and lighter border color.
/// [isHandCapture] — widens the frame and shows a hand icon instead of
///                   a single fingerprint, for multi-finger hand captures.
class FingerprintOverlay extends StatefulWidget {
  final bool isScanning;
  final bool isHandCapture;

  const FingerprintOverlay({
    super.key,
    this.isScanning = false,
    this.isHandCapture = false,
  });

  @override
  State<FingerprintOverlay> createState() => _FingerprintOverlayState();
}

class _FingerprintOverlayState extends State<FingerprintOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double w = widget.isHandCapture ? 300 : 240;
    final double h = widget.isHandCapture ? 200 : 240;
    const double radius = 16.0;
    const double bracketLen = 28.0;
    const double bracketW = 3.5;

    final borderColor =
        widget.isScanning ? AppColors.primaryLight : AppColors.primary;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Background tint ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: AppColors.primary.withValues(alpha: 0.04),
            ),
          ),

          // ── Border ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: borderColor.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),

          // ── Ghost icon (hand or single fingerprint) ──────────────────
          Center(
            child: widget.isHandCapture
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.back_hand_outlined,
                        size: 80,
                        color: AppColors.primary.withValues(alpha: 0.14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '4 fingers · spread apart',
                        style: TextStyle(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    Icons.fingerprint,
                    size: 110,
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
          ),

          // ── Animated scan line ───────────────────────────────────────
          if (widget.isScanning)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                const double topPad = 12.0;
                const double botPad = 12.0;
                final double top =
                    topPad + (h - topPad - botPad) * _ctrl.value;
                return Positioned(
                  top: top,
                  left: 12,
                  right: 12,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primaryLight.withValues(alpha: 0.9),
                          AppColors.primaryLight,
                          AppColors.primaryLight.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── Corner brackets ──────────────────────────────────────────
          _Bracket(
              corner: _Corner.topLeft, len: bracketLen, w: bracketW, color: borderColor, radius: radius),
          _Bracket(
              corner: _Corner.topRight, len: bracketLen, w: bracketW, color: borderColor, radius: radius),
          _Bracket(
              corner: _Corner.bottomLeft, len: bracketLen, w: bracketW, color: borderColor, radius: radius),
          _Bracket(
              corner: _Corner.bottomRight, len: bracketLen, w: bracketW, color: borderColor, radius: radius),
        ],
      ),
    );
  }
}

// ── Corner bracket ────────────────────────────────────────────────────────────

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _Bracket extends StatelessWidget {
  final _Corner corner;
  final double len;
  final double w;
  final Color color;
  final double radius;

  const _Bracket({
    required this.corner,
    required this.len,
    required this.w,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft   = corner == _Corner.topLeft   || corner == _Corner.bottomLeft;
    final isTop    = corner == _Corner.topLeft    || corner == _Corner.topRight;
    final hs       = w / 2;

    return Positioned(
      top:    isTop    ? 0 : null,
      bottom: !isTop   ? 0 : null,
      left:   isLeft   ? 0 : null,
      right:  !isLeft  ? 0 : null,
      child: SizedBox(
        width: len + hs,
        height: len + hs,
        child: CustomPaint(
          painter: _BracketPainter(
            corner: corner,
            color: color,
            len: len,
            strokeWidth: w,
            radius: radius,
          ),
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final _Corner corner;
  final Color color;
  final double len;
  final double strokeWidth;
  final double radius;

  _BracketPainter({
    required this.corner,
    required this.color,
    required this.len,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final half = strokeWidth / 2;

    switch (corner) {
      case _Corner.topLeft:
        canvas.drawLine(Offset(half, len), Offset(half, radius), paint);
        canvas.drawLine(Offset(radius, half), Offset(len, half), paint);
      case _Corner.topRight:
        canvas.drawLine(
            Offset(size.width - half, len), Offset(size.width - half, radius), paint);
        canvas.drawLine(
            Offset(size.width - radius, half), Offset(size.width - len, half), paint);
      case _Corner.bottomLeft:
        canvas.drawLine(
            Offset(half, size.height - len), Offset(half, size.height - radius), paint);
        canvas.drawLine(
            Offset(radius, size.height - half), Offset(len, size.height - half), paint);
      case _Corner.bottomRight:
        canvas.drawLine(
            Offset(size.width - half, size.height - len),
            Offset(size.width - half, size.height - radius),
            paint);
        canvas.drawLine(
            Offset(size.width - radius, size.height - half),
            Offset(size.width - len, size.height - half),
            paint);
    }
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.corner != corner;
}
