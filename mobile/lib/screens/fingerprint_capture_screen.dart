import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
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
  XFile? _capturedImage;

  Future<void> _openCamera() async {
    final XFile? result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          title: widget.isRegistration
              ? 'Capture Fingerprint'
              : 'Scan Fingerprint',
          showFingerprintOverlay: true,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _capturedImage = result);
    }
  }

  void _proceedToPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintPreviewScreen(
          patientName: widget.patientName,
          patientId: widget.patientId,
          isRegistration: widget.isRegistration,
          capturedImage: _capturedImage,
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
                const SizedBox(height: 24),
              ],

              // Preview / placeholder area
              Expanded(
                child: _capturedImage == null
                    ? _PlaceholderArea(onOpenCamera: _openCamera)
                    : _CapturedPreview(
                        imagePath: _capturedImage!.path,
                        onRetake: _openCamera,
                      ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              if (_capturedImage == null)
                PrimaryButton(
                  label: 'Open Camera',
                  icon: Icons.camera_alt,
                  onPressed: _openCamera,
                )
              else ...[
                PrimaryButton(
                  label: 'Confirm & Continue',
                  icon: Icons.check,
                  onPressed: _proceedToPreview,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Retake',
                  icon: Icons.refresh,
                  onPressed: _openCamera,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Shown before any image is captured.
class _PlaceholderArea extends StatelessWidget {
  final VoidCallback onOpenCamera;

  const _PlaceholderArea({required this.onOpenCamera});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenCamera,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt,
                  color: AppColors.primaryLight, size: 38),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tap to open camera',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place finger inside the frame when prompted',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after an image is captured — displays the thumbnail.
class _CapturedPreview extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRetake;

  const _CapturedPreview(
      {required this.imagePath, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            File(imagePath),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
            ),
          ),
        ),
        // Success badge
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Fingerprint captured',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
