import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FingerprintOverlay extends StatefulWidget {
  final bool isScanning;

  const FingerprintOverlay({super.key, this.isScanning = false});

  @override
  State<FingerprintOverlay> createState() => _FingerprintOverlayState();
}

class _FingerprintOverlayState extends State<FingerprintOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isScanning ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isScanning
                    ? AppColors.primaryLight
                    : AppColors.primary,
                width: 3,
              ),
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Corner guides
                Positioned(
                  top: 20,
                  left: 20,
                  child: _cornerGuide(topLeft: true),
                ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: _cornerGuide(topRight: true),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: _cornerGuide(bottomLeft: true),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: _cornerGuide(bottomRight: true),
                ),
                // Fingerprint icon
                Icon(
                  Icons.fingerprint,
                  size: 100,
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
                if (widget.isScanning)
                  // Scan line
                  Positioned(
                    child: _ScanLine(animation: _controller),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cornerGuide({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _CornerPainter(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }
}

class _ScanLine extends StatelessWidget {
  final AnimationController animation;

  const _ScanLine({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: 160,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.primaryLight.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool topLeft, topRight, bottomLeft, bottomRight;

  _CornerPainter({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (topLeft) {
      canvas.drawLine(Offset(0, size.height), const Offset(0, 0), paint);
      canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
      canvas.drawLine(
          Offset(size.width, 0), Offset(size.width, size.height), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint);
      canvas.drawLine(
          Offset(0, size.height), Offset(size.width, size.height), paint);
    }
    if (bottomRight) {
      canvas.drawLine(
          Offset(size.width, 0), Offset(size.width, size.height), paint);
      canvas.drawLine(
          Offset(0, size.height), Offset(size.width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
