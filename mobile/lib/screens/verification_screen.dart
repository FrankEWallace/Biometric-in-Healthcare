import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/fingerprint_overlay.dart';
import 'result_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _isScanning = false;
  bool _captured = false;
  bool _isVerifying = false;

  void _startCapture() {
    setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _captured = true;
        });
      }
    });
  }

  void _verify() async {
    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Demo: simulate a match — replace with real API call
    const bool matched = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ResultScreen(
          isSuccess: matched,
          patientName: 'Ahmed Kadic',
          patientId: 'PAT-00421',
          isRegistration: false,
        ),
      ),
    );
    setState(() => _isVerifying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Patient')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // Instruction banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ask the patient to place their registered finger on camera.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Camera preview
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FingerprintOverlay(isScanning: _isScanning),

                      Positioned(
                        bottom: 24,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _captured
                              ? _Chip(
                                  key: const ValueKey('done'),
                                  label: 'Fingerprint captured',
                                  icon: Icons.check_circle,
                                  color: AppColors.success,
                                )
                              : _isScanning
                                  ? _Chip(
                                      key: const ValueKey('scan'),
                                      label: 'Scanning...',
                                      icon: Icons.sensors,
                                      color: AppColors.primaryLight,
                                    )
                                  : _Chip(
                                      key: const ValueKey('idle'),
                                      label: 'Place finger inside the frame',
                                      icon: Icons.touch_app,
                                      color: Colors.white70,
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (!_captured)
                PrimaryButton(
                  label: _isScanning ? 'Scanning...' : 'Scan Fingerprint',
                  icon: Icons.fingerprint,
                  onPressed: _isScanning ? null : _startCapture,
                  isLoading: _isScanning,
                )
              else ...[
                PrimaryButton(
                  label: 'Verify Identity',
                  icon: Icons.verified_user,
                  onPressed: _isVerifying ? null : _verify,
                  isLoading: _isVerifying,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Retake',
                  icon: Icons.refresh,
                  onPressed: () => setState(() {
                    _captured = false;
                    _isScanning = false;
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
