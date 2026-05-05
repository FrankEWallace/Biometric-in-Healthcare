import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SnackStatus { success, error, warning, info }

void showStatusSnackbar(
  BuildContext context, {
  required String message,
  SnackStatus status = SnackStatus.success,
}) {
  final (icon, bg) = switch (status) {
    SnackStatus.success => (Icons.check_circle_rounded,    AppColors.success),
    SnackStatus.error   => (Icons.cancel_rounded,          AppColors.error),
    SnackStatus.warning => (Icons.warning_rounded,         AppColors.warning),
    SnackStatus.info    => (Icons.info_rounded,            AppColors.primary),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}
