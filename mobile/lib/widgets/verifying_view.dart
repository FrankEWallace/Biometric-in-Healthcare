import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Centered progress state shown while a biometric verify/identify request is
/// in flight. [title] and [subtitle] carry the per-screen messaging (each
/// screen describes what it is matching against).
///
/// Consolidated from four drifted private `_VerifyingView` copies whose only
/// difference was these two strings (plan 012b part C).
class VerifyingView extends StatelessWidget {
  final String title;
  final String subtitle;

  const VerifyingView({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
