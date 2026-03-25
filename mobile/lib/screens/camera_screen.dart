import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/fingerprint_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fingerprint_overlay.dart';

/// Full-screen camera that handles capture → preview → upload in one place.
///
/// Returns an [XFile] via [Navigator.pop] after a successful upload,
/// or `null` if the user cancels.
class CameraScreen extends StatefulWidget {
  final String title;
  final bool showFingerprintOverlay;

  /// Optional patient ID forwarded to the upload endpoint.
  final String? patientId;

  const CameraScreen({
    super.key,
    this.title = 'Capture Image',
    this.showFingerprintOverlay = false,
    this.patientId,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// ── Enum to track which "page" the user is on ────────────────────────────────
enum _Stage { initializing, live, preview, uploading }

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // Camera
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  // Capture
  XFile? _capturedImage;

  // UI
  _Stage _stage = _Stage.initializing;
  bool _isCapturing = false;
  String? _cameraError;

  // ── Lifecycle ────────────────────────────────────────────────────────────

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ctrl.dispose();
      if (mounted) setState(() => _stage = _Stage.initializing);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ──────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() {
      _stage = _Stage.initializing;
      _cameraError = null;
    });

    try {
      _cameras = await availableCameras();
    } catch (_) {
      if (mounted) {
        setState(() => _cameraError = 'No camera available on this device.');
      }
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) {
        setState(() => _cameraError = 'No camera found on this device.');
      }
      return;
    }

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final ctrl = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = _friendlyCameraError(e));
      return;
    }

    if (mounted) setState(() => _stage = _Stage.live);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    final current = _controller!.description.lensDirection;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != current,
      orElse: () => _cameras.first,
    );
    await _controller!.dispose();
    _controller = null;
    setState(() => _stage = _Stage.initializing);
    final ctrl = CameraController(next, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (mounted) setState(() => _stage = _Stage.live);
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = _friendlyCameraError(e));
    }
  }

  // ── Capture ──────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final file = await ctrl.takePicture();
      if (await File(file.path).exists() && mounted) {
        setState(() {
          _capturedImage = file;
          _stage = _Stage.preview;
          _isCapturing = false;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        _showSnackbar(_friendlyCameraError(e), isError: true);
        setState(() => _isCapturing = false);
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedImage = null;
      _stage = _Stage.live;
    });
  }

  // ── Upload ───────────────────────────────────────────────────────────────

  Future<void> _confirmAndUpload() async {
    final image = _capturedImage;
    if (image == null) return;

    final token = context.read<AuthProvider>().user?.token;
    if (token == null) {
      _showSnackbar('Session expired. Please log in again.', isError: true);
      return;
    }

    setState(() => _stage = _Stage.uploading);

    try {
      await FingerprintService().uploadFingerprint(
        File(image.path),
        token: token,
        patientId: widget.patientId,
      );
      if (mounted) Navigator.pop(context, image);
    } on FingerprintException catch (e) {
      if (mounted) {
        _showSnackbar(e.message, isError: true);
        setState(() => _stage = _Stage.preview);
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _friendlyCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return 'Camera permission denied. Enable it in Settings.';
      default:
        return e.description ?? 'An unexpected camera error occurred.';
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_appBarTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildContent()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  String get _appBarTitle {
    switch (_stage) {
      case _Stage.preview:
        return 'Review Image';
      case _Stage.uploading:
        return 'Uploading…';
      default:
        return widget.title;
    }
  }

  Widget _buildContent() {
    // Camera error
    if (_cameraError != null) {
      return _CameraErrorView(message: _cameraError!, onRetry: _initCamera);
    }

    // Preview / Uploading — show captured image
    if (_stage == _Stage.preview || _stage == _Stage.uploading) {
      return _ImagePreview(
        imagePath: _capturedImage!.path,
        isUploading: _stage == _Stage.uploading,
      );
    }

    // Initializing
    if (_stage == _Stage.initializing || _controller == null) {
      return const _LoadingView();
    }

    // Live viewfinder
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.previewSize?.height ?? 1,
              height: _controller!.value.previewSize?.width ?? 1,
              child: CameraPreview(_controller!),
            ),
          ),
          if (widget.showFingerprintOverlay)
            const Center(child: FingerprintOverlay(isScanning: false)),
          if (_isCapturing)
            Container(color: Colors.white.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    switch (_stage) {
      // ── Live viewfinder controls ──────────────────────────────────────
      case _Stage.live:
      case _Stage.initializing:
        final ready = _stage == _Stage.live && !_isCapturing;
        return Container(
          color: Colors.black,
          padding:
              const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleButton(
                icon: Icons.close,
                tooltip: 'Cancel',
                color: Colors.white24,
                iconColor: Colors.white,
                size: 52,
                onTap: () => Navigator.pop(context, null),
              ),
              _ShutterButton(
                isCapturing: _isCapturing,
                enabled: ready,
                onTap: _capture,
              ),
              _CircleButton(
                icon: Icons.cameraswitch_rounded,
                tooltip: 'Switch camera',
                color: _cameras.length > 1
                    ? Colors.white24
                    : Colors.transparent,
                iconColor: _cameras.length > 1
                    ? Colors.white
                    : Colors.transparent,
                size: 52,
                onTap: _cameras.length > 1 ? _switchCamera : null,
              ),
            ],
          ),
        );

      // ── Preview / Uploading controls ─────────────────────────────────
      case _Stage.preview:
      case _Stage.uploading:
        final uploading = _stage == _Stage.uploading;
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Row(
            children: [
              // Retake
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: uploading ? null : _retake,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: uploading
                            ? Colors.white24
                            : Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retake',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 16),
              // Confirm / uploading
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: uploading ? null : _confirmAndUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.6),
                  ),
                  child: uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Confirm & Upload',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Shows the captured image with an optional uploading overlay.
class _ImagePreview extends StatelessWidget {
  final String imagePath;
  final bool isUploading;

  const _ImagePreview(
      {required this.imagePath, required this.isUploading});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
          ),
        ),
        // Uploading dimmer + spinner
        if (isUploading) ...[
          Container(color: Colors.black.withValues(alpha: 0.55)),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
                SizedBox(height: 16),
                Text(
                  'Uploading fingerprint…',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
        // "Review" badge when not uploading
        if (!isUploading)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.preview, color: Colors.white70, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'Review before uploading',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white54),
          SizedBox(height: 16),
          Text('Starting camera…',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CameraErrorView({required this.message, required this.onRetry});

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
            Text(message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 14)),
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

class _ShutterButton extends StatelessWidget {
  final bool isCapturing;
  final bool enabled;
  final VoidCallback onTap;

  const _ShutterButton(
      {required this.isCapturing,
      required this.enabled,
      required this.onTap});

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
          border: Border.all(color: Colors.white54, width: 3),
        ),
        child: isCapturing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2.5),
              )
            : const Icon(Icons.camera_alt,
                color: AppColors.primary, size: 32),
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
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: iconColor, size: size * 0.45),
        ),
      ),
    );
  }
}
