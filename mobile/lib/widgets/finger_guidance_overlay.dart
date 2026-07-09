import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/finger_guidance/finger_guidance_state.dart';

/// Draws one tracked box over each detected fingertip pad so the user can see
/// exactly which four regions will be captured.
///
/// Landmarks arrive in normalized, unrotated sensor coordinates. The camera
/// preview is rendered full-screen with a cover fit of the upright (rotated)
/// frame, so this painter applies the same rotation + cover transform to map
/// each landmark onto screen pixels.
class FingerGuidanceOverlay extends StatelessWidget {
  final FingerGuidanceState state;

  /// Raw sensor preview size (landscape, e.g. 640×480).
  final Size previewSize;
  final int sensorOrientation;

  const FingerGuidanceOverlay({
    super.key,
    required this.state,
    required this.previewSize,
    required this.sensorOrientation,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FingerBoxPainter(
          state: state,
          previewSize: previewSize,
          sensorOrientation: sensorOrientation,
        ),
      ),
    );
  }
}

class _FingerBoxPainter extends CustomPainter {
  final FingerGuidanceState state;
  final Size previewSize;
  final int sensorOrientation;

  _FingerBoxPainter({
    required this.state,
    required this.previewSize,
    required this.sensorOrientation,
  });

  static const _tooFarColor = Color(0xFFFB8C00); // amber
  static const _holdColor = Color(0xFFFB8C00); // amber
  static const _readyColor = Color(0xFF43A047); // green

  Color get _statusColor => switch (state.status) {
        GuidanceStatus.tooFar => _tooFarColor,
        GuidanceStatus.holdStill => _holdColor,
        GuidanceStatus.ready => _readyColor,
        GuidanceStatus.searching => Colors.transparent,
      };

  /// Normalized sensor point → screen pixels (rotate upright, then cover-fit).
  Offset _toScreen(Offset p, Size canvas) {
    final double rx, ry;
    switch (sensorOrientation) {
      case 90:
        rx = 1 - p.dy;
        ry = p.dx;
      case 180:
        rx = 1 - p.dx;
        ry = 1 - p.dy;
      case 270:
        rx = p.dy;
        ry = 1 - p.dx;
      default:
        rx = p.dx;
        ry = p.dy;
    }
    final upright = sensorOrientation % 180 == 0
        ? previewSize
        : Size(previewSize.height, previewSize.width);
    final scale =
        math.max(canvas.width / upright.width, canvas.height / upright.height);
    final offX = (canvas.width - upright.width * scale) / 2;
    final offY = (canvas.height - upright.height * scale) / 2;
    return Offset(
      rx * upright.width * scale + offX,
      ry * upright.height * scale + offY,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (state.fingers.isEmpty || previewSize.isEmpty) return;

    final color = _statusColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    final fill = Paint()..color = color.withValues(alpha: 0.10);
    final dot = Paint()..color = color.withValues(alpha: 0.9);

    for (final finger in state.fingers) {
      final tip = _toScreen(finger.tip, size);
      final dip = _toScreen(finger.dip, size);
      final axis = tip - dip;
      final len = axis.distance;
      if (len < 4) continue;

      // The fingerprint pad sits between the DIP joint and the tip — box it,
      // aligned with the finger axis.
      final center = dip + axis * 0.65;
      final angle = math.atan2(axis.dy, axis.dx);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + math.pi / 2); // finger axis points "up" in box space
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: len * 1.4, height: len * 1.8),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);
      canvas.restore();

      canvas.drawCircle(tip, 3, dot);
    }
  }

  @override
  bool shouldRepaint(_FingerBoxPainter old) =>
      old.state != state ||
      old.previewSize != previewSize ||
      old.sensorOrientation != sensorOrientation;
}
