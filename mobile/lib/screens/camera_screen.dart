import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/fingerprint_overlay.dart';

/// A full-screen camera screen that shows a live preview, an optional
/// fingerprint guide overlay, and a capture button.
///
/// Returns an [XFile] to the caller via [Navigator.pop] when a photo is taken,
/// or `null` if the user cancels.
class CameraScreen extends StatefulWidget {
  /// Label shown in the AppBar.
  final String title;

  /// When true the fingerprint guide overlay is rendered on the preview.
  final bool showFingerprintOverlay;

  const CameraScreen({
    super.key,
    this.title = 'Capture Image',
    this.showFingerprintOverlay = false,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Pause/resume camera when the app goes to background/foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitialized = false;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'No camera available on this device.');
      }
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) {
        setState(() => _errorMessage = 'No camera found on this device.');
      }
      return;
    }

    // Prefer back camera; fall back to first available.
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = controller;

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _friendlyError(e));
      }
      return;
    }

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  Future<void> _captureImage() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile image = await controller.takePicture();
      // The image is saved to a system temp path by the camera plugin.
      // Verify the file exists before returning it.
      if (await File(image.path).exists() && mounted) {
        Navigator.pop(context, image);
      }
    } on CameraException catch (e) {
      if (mounted) {
        _showError(_friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  String _friendlyError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return 'Camera permission denied. Please enable it in Settings.';
      case 'AudioAccessDenied':
        return 'Microphone permission denied.';
      default:
        return e.description ?? 'An unexpected camera error occurred.';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Camera preview ──────────────────────────────────────────
            Expanded(
              child: _buildPreview(),
            ),

            // ── Bottom controls ──────────────────────────────────────────
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // Error state
    if (_errorMessage != null) {
      return _CameraError(
        message: _errorMessage!,
        onRetry: _initCamera,
      );
    }

    // Loading / initializing state
    if (!_isInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Starting camera…',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Live preview
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          // Fill the available space while keeping the camera aspect ratio.
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.previewSize?.height ?? 1,
              height: _controller!.value.previewSize?.width ?? 1,
              child: CameraPreview(_controller!),
            ),
          ),

          // Optional fingerprint guide overlay
          if (widget.showFingerprintOverlay)
            const Center(child: FingerprintOverlay(isScanning: false)),

          // Capture flash animation
          if (_isCapturing)
            Container(color: Colors.white.withValues(alpha: 0.25)),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Cancel
          _CircleButton(
            icon: Icons.close,
            tooltip: 'Cancel',
            color: Colors.white24,
            iconColor: Colors.white,
            size: 52,
            onTap: () => Navigator.pop(context, null),
          ),

          // Shutter
          _ShutterButton(
            isCapturing: _isCapturing,
            enabled: _isInitialized && !_isCapturing,
            onTap: _captureImage,
          ),

          // Switch camera (only if multiple cameras)
          _CircleButton(
            icon: Icons.cameraswitch_rounded,
            tooltip: 'Switch camera',
            color: _cameras.length > 1 ? Colors.white24 : Colors.transparent,
            iconColor:
                _cameras.length > 1 ? Colors.white : Colors.transparent,
            size: 52,
            onTap: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;

    final currentDirection = _controller!.description.lensDirection;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != currentDirection,
      orElse: () => _cameras.first,
    );

    await _controller!.dispose();
    _controller = null;
    setState(() => _isInitialized = false);

    final controller = CameraController(
      next,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } on CameraException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e));
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _ShutterButton extends StatelessWidget {
  final bool isCapturing;
  final bool enabled;
  final VoidCallback onTap;

  const _ShutterButton({
    required this.isCapturing,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.white38,
          border: Border.all(
            color: Colors.white54,
            width: 3,
          ),
        ),
        child: isCapturing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(
                Icons.camera_alt,
                color: AppColors.primary,
                size: 32,
              ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback? onTap;

  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.iconColor,
    required this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: iconColor, size: size * 0.45),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CameraError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
