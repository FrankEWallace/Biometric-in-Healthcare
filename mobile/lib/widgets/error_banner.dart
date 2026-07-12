import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dismissible inline error banner used across the verify/enroll/registration
/// screens. Shows an error icon, the [message], and a close affordance.
///
/// When [onRetry] is provided, a "Retry" button is rendered below the message —
/// the superset behavior that the fingerprint verify screen needs.
///
/// Consolidated from six drifted private `_ErrorBanner` copies (plan 012b part C).
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  /// When provided, shows a "Retry" button inside the banner.
  final VoidCallback? onRetry;

  const ErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline,
                    color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13, height: 1.4),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, color: AppColors.error, size: 16),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
