import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'result_screen.dart';

class FingerprintPreviewScreen extends StatefulWidget {
  final String? patientName;
  final String? patientId;
  final bool isRegistration;

  const FingerprintPreviewScreen({
    super.key,
    this.patientName,
    this.patientId,
    this.isRegistration = false,
  });

  @override
  State<FingerprintPreviewScreen> createState() =>
      _FingerprintPreviewScreenState();
}

class _FingerprintPreviewScreenState extends State<FingerprintPreviewScreen> {
  bool _isSaving = false;

  void _confirmAndSave() async {
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (widget.isRegistration) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            isSuccess: true,
            patientName: widget.patientName,
            patientId: widget.patientId,
            isRegistration: true,
          ),
        ),
        (route) => route.isFirst,
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            isSuccess: true,
            patientName: widget.patientName,
            patientId: widget.patientId,
            isRegistration: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Fingerprint'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // Quality indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.success, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Good quality — fingerprint is clear',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Fingerprint preview card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 3),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        size: 100,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Metadata row
                    if (widget.patientName != null) ...[
                      _DetailRow(
                          label: 'Patient Name',
                          value: widget.patientName!),
                      const SizedBox(height: 8),
                    ],
                    if (widget.patientId != null) ...[
                      _DetailRow(
                          label: 'Patient ID', value: widget.patientId!),
                      const SizedBox(height: 8),
                    ],
                    _DetailRow(label: 'Capture Quality', value: 'High (94%)'),
                    const SizedBox(height: 8),
                    _DetailRow(
                        label: 'Timestamp',
                        value: _currentTime()),
                  ],
                ),
              ),
              const Spacer(),

              PrimaryButton(
                label:
                    widget.isRegistration ? 'Confirm & Save' : 'Confirm & Verify',
                icon: Icons.save,
                onPressed: _confirmAndSave,
                isLoading: _isSaving,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Retake',
                icon: Icons.refresh,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
