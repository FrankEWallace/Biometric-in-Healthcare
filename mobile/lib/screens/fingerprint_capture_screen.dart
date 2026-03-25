import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/fingerprint_overlay.dart';
import 'fingerprint_preview_screen.dart';

class FingerprintCaptureScreen extends StatefulWidget {
  final String? patientName;
  final String? patientId;
  final bool isRegistration;

  const FingerprintCaptureScreen({
    super.key,
    this.patientName,
    this.patientId,
    this.isRegistration = false,
  });

  @override
  State<FingerprintCaptureScreen> createState() =>
      _FingerprintCaptureScreenState();
}

class _FingerprintCaptureScreenState extends State<FingerprintCaptureScreen> {
  bool _isScanning = false;
  bool _captured = false;

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

  void _proceedToPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintPreviewScreen(
          patientName: widget.patientName,
          patientId: widget.patientId,
          isRegistration: widget.isRegistration,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isRegistration ? 'Capture Fingerprint' : 'Scan Fingerprint',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // Patient info banner (registration only)
              if (widget.isRegistration && widget.patientName != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.patientName}  ·  ${widget.patientId}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Camera preview placeholder
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
                      // Simulated camera background
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          color: const Color(0xFF0F1923),
                        ),
                      ),

                      // Finger placement overlay
                      FingerprintOverlay(isScanning: _isScanning),

                      // Bottom instruction
                      Positioned(
                        bottom: 24,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _captured
                              ? _StatusChip(
                                  key: const ValueKey('captured'),
                                  label: 'Fingerprint captured!',
                                  icon: Icons.check_circle,
                                  color: AppColors.success,
                                )
                              : _isScanning
                                  ? _StatusChip(
                                      key: const ValueKey('scanning'),
                                      label: 'Scanning...',
                                      icon: Icons.sensors,
                                      color: AppColors.primaryLight,
                                    )
                                  : _StatusChip(
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

              // Action buttons
              if (!_captured) ...[
                PrimaryButton(
                  label: _isScanning ? 'Scanning...' : 'Capture',
                  icon: Icons.camera_alt,
                  onPressed: _isScanning ? null : _startCapture,
                  isLoading: _isScanning,
                ),
              ] else ...[
                PrimaryButton(
                  label: 'Confirm & Continue',
                  icon: Icons.check,
                  onPressed: _proceedToPreview,
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

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusChip({
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
