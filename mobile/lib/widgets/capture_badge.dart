import 'package:flutter/material.dart';

/// Small pill badge overlaid on a captured-image preview (e.g. "Captured",
/// "Retake"). Named `CaptureBadge` to avoid colliding with Material's `Badge`.
///
/// Consolidated from three identical private `_Badge` copies (plan 012b part C).
class CaptureBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const CaptureBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
