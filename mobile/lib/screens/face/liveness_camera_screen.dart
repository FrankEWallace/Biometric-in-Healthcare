import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../controllers/liveness_controller.dart';
import '../../theme/app_theme.dart';

/// Full-screen liveness check: blink → head-turn → automatic capture.
///
/// Returns an [XFile] on success, or `null` if the user cancels.
/// Replace the plain [CameraScreen] call in face enroll/verify flows.
class LivenessCameraScreen extends StatefulWidget {
  const LivenessCameraScreen({super.key});

  @override
  State<LivenessCameraScreen> createState() => _LivenessCameraScreenState();
}

class _LivenessCameraScreenState extends State<LivenessCameraScreen>
    with WidgetsBindingObserver {
  // Camera
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _initialized = false;
  String? _cameraError;

  // ML Kit
  late final FaceDetector _detector;

  // Liveness state machine
  late final LivenessController _liveness;
  bool _isProcessing = false;
  bool _isCaptured = false;
  bool _faceDetected = false;

  // Orientation map for Android rotation compensation
  static final _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // eye open probabilities
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _liveness = LivenessController();
    _liveness.addListener(_onLivenessChanged);

    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveness.removeListener(_onLivenessChanged);
    _liveness.dispose();
    _detector.close();
    _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ctrl.stopImageStream();
      ctrl.dispose();
      _controller = null;
      if (mounted) setState(() => _initialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (mounted) {
      setState(() {
        _initialized = false;
        _cameraError = null;
      });
    }

    try {
      _cameras = await availableCameras();
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'No camera available on this device.');
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _cameraError = 'No camera found.');
      return;
    }

    // Default to back camera (staff points at patient)
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // Android; iOS ignores this
    );
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError = _friendlyCameraError(e));
      }
      return;
    }

    if (!mounted) return;
    setState(() => _initialized = true);

    // Short delay so the viewfinder settles before the state machine starts
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    _liveness.start();
    _startStream();
  }

  void _startStream() {
    _controller?.startImageStream((CameraImage image) {
      if (_isProcessing || _isCaptured) return;
      _isProcessing = true;
      _processFrame(image).whenComplete(() => _isProcessing = false);
    });
  }

  // ── Frame processing ───────────────────────────────────────────────────────

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) return;
    try {
      final faces = await _detector.processImage(inputImage);
      final detected = faces.isNotEmpty;
      if (detected != _faceDetected && mounted) {
        setState(() => _faceDetected = detected);
      }
      _liveness.processFaces(faces);
    } catch (_) {
      // ignore individual frame errors
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final ctrl = _controller;
    if (ctrl == null) return null;

    final camera = ctrl.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var compensation =
          _orientations[ctrl.value.deviceOrientation] ?? 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        compensation = (sensorOrientation + compensation) % 360;
      } else {
        compensation = (sensorOrientation - compensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Single-plane (iOS BGRA8888)
    if (image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // Multi-plane (Android NV21 / YUV_420_888)
    final WriteBuffer buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return InputImage.fromBytes(
      bytes: buffer.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  // ── Liveness callbacks ─────────────────────────────────────────────────────

  void _onLivenessChanged() {
    if (!mounted) return;
    setState(() {});

    if (_liveness.isPassed && !_isCaptured) {
      _isCaptured = true;
      _captureStill();
    }
  }

  Future<void> _captureStill() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      await ctrl.stopImageStream();
      final image = await ctrl.takePicture();
      if (mounted) Navigator.pop(context, image);
    } catch (_) {
      // Capture failed — let the user retry
      if (mounted) {
        setState(() => _isCaptured = false);
        _liveness.reset();
        _liveness.start();
        _startStream();
      }
    }
  }

  void _retry() {
    setState(() => _isCaptured = false);
    _liveness.reset();
    _liveness.start();
    // Restart stream if it stopped
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized &&
        !ctrl.value.isStreamingImages) {
      _startStream();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    final current = _controller!.description.lensDirection;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != current,
      orElse: () => _cameras.first,
    );

    await _controller!.stopImageStream();
    await _controller!.dispose();
    _controller = null;
    setState(() => _initialized = false);

    final ctrl = CameraController(
      next,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = _friendlyCameraError(e));
      return;
    }

    if (!mounted) return;
    setState(() => _initialized = true);
    _liveness.reset();
    setState(() => _isCaptured = false);
    _liveness.start();
    _startStream();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendlyCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'cameraPermission':
        return 'Camera permission denied. Open Settings and allow camera access.';
      default:
        return e.description ?? 'Camera error (${e.code}).';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Liveness Check'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildViewfinder()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_cameraError != null) {
      return _ErrorView(message: _cameraError!, onRetry: _initCamera);
    }
    if (!_initialized || _controller == null) {
      return const _LoadingView();
    }

    return Stack(
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
        // Oval + dark surround
        Positioned.fill(
          child: _LivenessOverlay(step: _liveness.step, faceDetected: _faceDetected),
        ),
        // Step progress dots
        Positioned(
          top: 20,
          child: _StepDots(step: _liveness.step),
        ),
        // Instruction strip
        Positioned(
          bottom: 12,
          left: 16,
          right: 16,
          child: _InstructionBanner(
            instruction: _faceDetected ? _liveness.instruction : 'Center your face in the oval',
            subInstruction: _faceDetected ? _liveness.subInstruction : 'No face detected',
            step: _liveness.step,
            faceDetected: _faceDetected,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    if (_liveness.isFailed) {
      return _FailedBar(
        onRetry: _retry,
        onCancel: () => Navigator.pop(context, null),
      );
    }

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, null),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
          if (_cameras.length > 1) ...[
            const SizedBox(width: 12),
            _CircleButton(
              icon: Icons.cameraswitch_rounded,
              tooltip: 'Switch camera',
              onTap: _switchCamera,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Liveness overlay ──────────────────────────────────────────────────────────

class _LivenessOverlay extends StatefulWidget {
  final LivenessStep step;
  final bool faceDetected;
  const _LivenessOverlay({required this.step, required this.faceDetected});

  @override
  State<_LivenessOverlay> createState() => _LivenessOverlayState();
}

class _LivenessOverlayState extends State<_LivenessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _colorForStep(LivenessStep step) {
    // Grey out the oval until a face is in frame (only during the waiting steps).
    if (!widget.faceDetected &&
        (step == LivenessStep.promptBlink || step == LivenessStep.idle)) {
      return Colors.white38;
    }
    switch (step) {
      case LivenessStep.promptBlink:
        return AppColors.primary;
      case LivenessStep.promptTurn:
        return AppColors.warning;
      case LivenessStep.capturing:
      case LivenessStep.passed:
        return AppColors.success;
      case LivenessStep.failed:
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForStep(widget.step);
    final isActive = widget.step == LivenessStep.promptBlink ||
        widget.step == LivenessStep.promptTurn;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final ovalW = w * 0.82;
        final ovalH = h * 0.68;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Dark surround
            CustomPaint(
              size: Size(w, h),
              painter: _SurroundPainter(
                ovalW: ovalW,
                ovalH: ovalH,
                cx: w / 2,
                cy: h / 2,
              ),
            ),
            // Animated oval border
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final borderColor = isActive
                    ? Color.lerp(color, Colors.white, _pulse.value * 0.3)!
                    : color;
                final opacity = isActive ? 0.6 + 0.4 * _pulse.value : 0.9;

                return SizedBox(
                  width: ovalW,
                  height: ovalH,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      borderRadius:
                          BorderRadius.all(Radius.elliptical(ovalW / 2, ovalH / 2)),
                      border: Border.all(
                        color: borderColor.withValues(alpha: opacity),
                        width: 2.5,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Ghost face icon
            Icon(
              Icons.face_outlined,
              size: ovalW * 0.40,
              color: color.withValues(alpha: 0.10),
            ),
          ],
        );
      },
    );
  }
}

class _SurroundPainter extends CustomPainter {
  final double ovalW, ovalH, cx, cy;
  const _SurroundPainter(
      {required this.ovalW,
      required this.ovalH,
      required this.cx,
      required this.cy});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCenter(
          center: Offset(cx, cy), width: ovalW, height: ovalH));
    canvas.drawPath(path..fillType = PathFillType.evenOdd, paint);
  }

  @override
  bool shouldRepaint(_SurroundPainter old) =>
      old.ovalW != ovalW || old.ovalH != ovalH;
}

// ── Step progress dots ────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final LivenessStep step;
  const _StepDots({required this.step});

  @override
  Widget build(BuildContext context) {
    final blinkDone = step == LivenessStep.promptTurn ||
        step == LivenessStep.capturing ||
        step == LivenessStep.passed;
    final turnDone =
        step == LivenessStep.capturing || step == LivenessStep.passed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(
            label: 'Blink',
            active: step == LivenessStep.promptBlink,
            done: blinkDone,
          ),
          const SizedBox(width: 8),
          _DotDivider(done: blinkDone),
          const SizedBox(width: 8),
          _Dot(
            label: 'Turn',
            active: step == LivenessStep.promptTurn,
            done: turnDone,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  const _Dot({required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : active
            ? Colors.white
            : Colors.white38;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppColors.success : (active ? Colors.white : Colors.white24)),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
    ]);
  }
}

class _DotDivider extends StatelessWidget {
  final bool done;
  const _DotDivider({required this.done});

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 1,
        color: done ? AppColors.success : Colors.white24,
      );
}

// ── Instruction banner ────────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  final String instruction;
  final String? subInstruction;
  final LivenessStep step;
  final bool faceDetected;

  const _InstructionBanner({
    required this.instruction,
    required this.subInstruction,
    required this.step,
    required this.faceDetected,
  });

  IconData _icon() {
    if (!faceDetected &&
        (step == LivenessStep.promptBlink || step == LivenessStep.idle)) {
      return Icons.face_outlined;
    }
    switch (step) {
      case LivenessStep.promptBlink:
        return Icons.visibility_outlined;
      case LivenessStep.promptTurn:
        return Icons.rotate_right_rounded;
      case LivenessStep.capturing:
      case LivenessStep.passed:
        return Icons.check_circle_outline_rounded;
      case LivenessStep.failed:
        return Icons.timer_off_outlined;
      default:
        return Icons.face_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(_icon(), color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  instruction,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                if (subInstruction != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subInstruction!,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Failed bottom bar ─────────────────────────────────────────────────────────

class _FailedBar extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  const _FailedBar({required this.onRetry, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.white54),
          SizedBox(height: 16),
          Text('Starting camera…',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

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
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
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

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _CircleButton(
      {required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.white24),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
