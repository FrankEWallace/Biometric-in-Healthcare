import 'package:flutter/material.dart';

/// Shows the ADR-013 "Access Restricted" dialog: the patient was identified
/// nationally, but is registered at another facility and their records are
/// withheld here. No PII is shown.
///
/// Consolidated from four private `_showAccessRestrictedDialog` copies across
/// the verify screens (plan 012b part C; the copies were seeded by plan 019).
Future<void> showAccessRestrictedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.lock_outline, color: Color(0xFF6B7280), size: 22),
        SizedBox(width: 8),
        Text('Access Restricted'),
      ]),
      content: const Text(
        'This patient was identified, but they are registered at another '
        'facility. You are not authorized to view their records here. '
        'Request access through a referral or the patient\'s consent.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
