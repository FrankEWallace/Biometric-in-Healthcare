import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/finger_guidance/finger_guidance_controller.dart';
import '../../providers/auth_provider.dart';
import '../../services/fingerprint_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/finger_guidance_overlay.dart';
import '../../widgets/fingerprint_overlay.dart';

/// Full-screen fingerprint capture with server-side optical-flow liveness check.
///
/// Captures [_frameTarget] stills in rapid succession, runs the liveness check,
/// and — if live — pops with the last [XFile]. Used by verification and by hand
/// enrollment (the server segments four fingers from the single hand photo).
///
/// Returns `null` if the user cancels.
class FingerprintLivenessCameraScreen extends StatefulWidget {
  final bool isHandCapture;
  final String? fingerLabel;

  const FingerprintLivenessCameraScreen({
    super.key,
    this.isHandCapture = true,
    this.fingerLabel,
  });

  @override
  State<FingerprintLivenessCameraScreen> createState() =>
      _FingerprintLivenessCameraScreenState();
}

// ── State ──────────────────────────────────────────────────────────────────────

enum _ScreenState { initializing, ready, capturing, checking, success, failed }

class _FingerprintLivenessCameraScreenState
    extends State<FingerprintLivenessCameraScreen>
    with WidgetsBindingObserver {
  // Camera
  List<CameraDescription> _cameras = [];
  CameraController? _controller;

  _ScreenState _screenState = _ScreenState.initializing;
  String? _cameraError;

  // Capture progress
  int _capturedCount = 0;
  static const int _frameTarget = 6;
  static const Duration _frameInterval = Duration(milliseconds: 120);

  // A3: sharpness gate — variance of 0-255 grayscale values on a 320px thumbnail.
  // Below this value the image is too blurry to send for liveness check.
  static const double _sharpnessThreshold = 300.0;

  // Auto-trigger: stream frames and fire when quality is good for 3 consecutive checks.
  final bool _autoTriggerEnabled = true;
  int _goodFrameStreak = 0;
  static const int _goodFramesRequired = 3;
  bool _streamChecking = false; // debounce: don't re-enter while checking quality

  // Realtime quality indicator fed by the image stream (0.0–1.0).
  double _liveQuality = 0.0;

  // Four-finger guidance (MediaPipe hand tracking on both Android and iOS).
  // Null only on web or in single-finger mode — the auto-trigger then falls
  // back to the sharpness-only gate.
  FingerGuidanceController? _guidance;
  StreamSubscription<FingerGuidanceState>? _guidanceSub;
  FingerGuidanceState _guidanceState = FingerGuidanceState.searching;

  // Failure details
  String? _errorMessage;
  double? _meanDisplacement;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isHandCapture) {
      _guidance = FingerGuidanceController.create();
      _guidanceSub = _guidance?.stream.listen((state) {
        if (mounted) setState(() => _guidanceState = state);
      });
    }
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guidanceSub?.cancel();
    _guidance?.dispose();
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
      _controller = null;
      if (mounted) setState(() => _screenState = _ScreenState.initializing);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (mounted) {
      setState(() {
        _screenState = _ScreenState.initializing;
        _cameraError = null;
      });
    }

    try {
      _cameras = await availableCameras();
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'No camera available.');
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _cameraError = 'No camera found.');
      return;
    }

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    // Stream format: 3-plane YUV420 on Android (what the sharpness gate and
    // MediaPipe hand tracking expect), BGRA on iOS. Stills are JPEG regardless.
    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = _friendlyError(e));
      return;
    }

    if (mounted) setState(() => _screenState = _ScreenState.ready);

    if (_autoTriggerEnabled) {
      ctrl.startImageStream(_onStreamFrame);
    }
  }

  // ── Auto-trigger stream handler ───────────────────────────────────────────

  Future<void> _onStreamFrame(CameraImage image) async {
    // Only run while in the ready state and not already processing a frame.
    if (_screenState != _ScreenState.ready || _streamChecking) return;
    _streamChecking = true;

    // Feed hand tracking (throttled internally to ~10 fps).
    _guidance?.processFrame(
        image, _controller?.description.sensorOrientation ?? 90);

    final quality = _quickQualityFromStream(image);
    if (mounted) setState(() => _liveQuality = (quality / _sharpnessThreshold).clamp(0.0, 1.0));

    // With hand tracking, capture also waits for four stable, close-enough
    // fingers; without it, the sharpness streak alone triggers.
    final guidanceReady = _guidance == null || _guidanceState.isReady;

    if (quality >= _sharpnessThreshold && guidanceReady) {
      _goodFrameStreak++;
      if (_goodFrameStreak >= _goodFramesRequired) {
        // Stop the stream before taking still pictures.
        await _controller?.stopImageStream();
        if (mounted && _screenState == _ScreenState.ready) {
          _startCapture();
        }
      }
    } else {
      _goodFrameStreak = 0;
    }

    _streamChecking = false;
  }

  /// Fast luma variance on a 1-in-8 pixel subsample.
  ///
  /// Android: YUV420/NV21 — plane 0 is the Y channel (1 byte per pixel).
  /// iOS:     BGRA8888    — single plane, 4 bytes per pixel; luma = 0.299R+0.587G+0.114B.
  double _quickQualityFromStream(CameraImage image) {
    try {
      final int w = image.width;
      final int h = image.height;
      final Uint8List bytes = image.planes[0].bytes;
      final int stride = image.planes[0].bytesPerRow;

      double sum = 0;
      double sumSq = 0;
      int n = 0;

      if (Platform.isIOS) {
        // BGRA8888: stride may be > w*4 on some devices.
        for (int row = 0; row < h; row += 8) {
          for (int col = 0; col < w; col += 8) {
            final int i = row * stride + col * 4;
            // BGRA order: bytes[i]=B, [i+1]=G, [i+2]=R, [i+3]=A
            final double v = bytes[i + 2] * 0.299 +
                             bytes[i + 1] * 0.587 +
                             bytes[i]     * 0.114;
            sum   += v;
            sumSq += v * v;
            n++;
          }
        }
      } else {
        // YUV420/NV21: plane 0 is Y, 1 byte per pixel.
        for (int row = 0; row < h; row += 8) {
          for (int col = 0; col < w; col += 8) {
            final double v = bytes[row * stride + col].toDouble();
            sum   += v;
            sumSq += v * v;
            n++;
          }
        }
      }

      if (n == 0) return 0;
      final mean = sum / n;
      return (sumSq / n) - (mean * mean); // variance
    } catch (_) {
      return 0;
    }
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  Future<void> _startCapture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    setState(() {
      _screenState    = _ScreenState.capturing;
      _capturedCount  = 0;
      _errorMessage   = null;
      _meanDisplacement = null;
    });

    // A3: lock focus + exposure to the centre before capturing so the hand
    // image is sharp. Best-effort — some devices don't support it.
    try {
      final size = ctrl.value.previewSize;
      if (size != null) {
        final center = Offset(size.height / 2, size.width / 2);
        await ctrl.setFocusPoint(center);
        await ctrl.setExposurePoint(center);
      }
      await ctrl.setFocusMode(FocusMode.locked);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));

    final frames = <XFile>[];

    for (int i = 0; i < _frameTarget; i++) {
      if (!mounted) return;
      try {
        final file = await ctrl.takePicture();
        frames.add(file);

        // A3: check sharpness on the first frame — fast-reject blurry captures
        // before running the full 6-frame liveness sequence.
        if (i == 0) {
          final sharpness = await _estimateSharpness(file);
          if (sharpness < _sharpnessThreshold) {
            if (mounted) {
              // Unlock focus so the viewfinder re-focuses on retry.
              ctrl.setFocusMode(FocusMode.auto).catchError((_) {});
              setState(() {
                _screenState  = _ScreenState.failed;
                _errorMessage = 'Image too blurry. Hold steady, ensure good '
                    'lighting, and try again.';
              });
            }
            return;
          }
        }

        if (mounted) setState(() => _capturedCount = i + 1);
        if (i < _frameTarget - 1) await Future.delayed(_frameInterval);
      } catch (_) {
        break;
      }
    }

    // Unlock focus so the viewfinder is live again if the user retries.
    ctrl.setFocusMode(FocusMode.auto).catchError((_) {});

    if (!mounted) return;

    if (frames.length < 2) {
      setState(() {
        _screenState  = _ScreenState.failed;
        _errorMessage = 'Could not capture enough frames. Try again.';
      });
      return;
    }

    // ── Liveness check ────────────────────────────────────────────────────

    setState(() => _screenState = _ScreenState.checking);

    final token = context.read<AuthProvider>().user?.token ?? '';

    try {
      final result = await FingerprintService().checkLiveness(
        frames,
        token: token,
      );

      if (!mounted) return;

      if (result.isLive) {
        await _showSuccessThenPop(frames.last);
      } else {
        setState(() {
          _screenState      = _ScreenState.failed;
          _meanDisplacement = result.meanDisplacement;
          _errorMessage     = _livenessFailureMessage(result.reason);
        });
      }
    } on FingerprintException catch (e) {
      if (mounted) {
        setState(() {
          _screenState  = _ScreenState.failed;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _screenState  = _ScreenState.failed;
          _errorMessage = 'Liveness check failed unexpectedly. Please try again.';
        });
      }
    }
  }

  /// Briefly shows a "Good Scan" confirmation so the user knows capture
  /// finished before the screen pops — without it, users can't tell whether
  /// the scan succeeded or the app just froze (the top NIST usability finding
  /// for unassisted fingerprint capture).
  Future<void> _showSuccessThenPop(Object popResult) async {
    if (!mounted) return;
    setState(() => _screenState = _ScreenState.success);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.pop(context, popResult);
  }

  void _retry() {
    setState(() {
      _screenState      = _ScreenState.ready;
      _errorMessage     = null;
      _meanDisplacement = null;
      _capturedCount    = 0;
      _goodFrameStreak  = 0;
      _liveQuality      = 0.0;
    });
    if (_autoTriggerEnabled) {
      _controller?.startImageStream(_onStreamFrame).catchError((_) {});
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _livenessFailureMessage(String reason) {
    switch (reason) {
      case 'no_hand':
        return 'No hand detected. Place your hand flat to fill the frame, then try again.';
      case 'static_image':
        return 'No movement detected. Ensure this is a real hand, not a photo or screen.';
      case 'insufficient_frames':
        return 'Too few frames captured. Hold still and try again.';
      case 'no_features':
        return 'No features detected. Place your hand closer to the camera.';
      default:
        return 'Liveness check did not pass. Please try again.';
    }
  }

  /// A3: Estimate image sharpness from a captured frame.
  ///
  /// Decodes the JPEG at 320×240 using [dart:ui], then computes the variance
  /// of grayscale pixel values over a subsample.  Sharp images have higher
  /// contrast across adjacent pixels → higher variance.  Blurry images are
  /// nearly uniform → low variance.
  ///
  /// Returns a large value (1000) on any decode error so a broken frame never
  /// blocks the capture flow.
  Future<double> _estimateSharpness(XFile frame) async {
    try {
      final bytes = await File(frame.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 320,
        targetHeight: 240,
      );
      final fi = await codec.getNextFrame();
      final bd = await fi.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      fi.image.dispose();
      codec.dispose();

      if (bd == null) return 1000.0;

      final px = bd.buffer.asUint8List();
      double sum = 0;
      double sumSq = 0;
      int n = 0;

      // Sample every 4th pixel (stride 16 in RGBA bytes) for speed.
      for (int i = 0; i < px.length - 3; i += 16) {
        final g = px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114;
        sum  += g;
        sumSq += g * g;
        n++;
      }

      if (n == 0) return 1000.0;
      final mean = sum / n;
      return (sumSq / n) - (mean * mean); // variance
    } catch (_) {
      return 1000.0; // fail open — don't block on unexpected decode errors
    }
  }

  String _friendlyError(CameraException e) {
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
        title: Text(widget.fingerLabel != null
            ? 'Scan — ${widget.fingerLabel}'
            : 'Fingerprint Scan'),
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
    if (_screenState == _ScreenState.initializing ||
        _controller == null) {
      return const _LoadingView(message: 'Starting camera…');
    }

    return LayoutBuilder(builder: (context, constraints) {
      final overlayW = constraints.maxWidth  * 0.75;
      final overlayH = constraints.maxHeight * 0.75;

      return Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          // Camera preview
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width:  _controller!.value.previewSize?.height ?? 1,
              height: _controller!.value.previewSize?.width  ?? 1,
              child: CameraPreview(_controller!),
            ),
          ),

          // Fingerprint frame overlay — hidden once hand tracking has locked
          // onto the fingers (the per-finger boxes replace the static guide).
          if (_guidance == null || _guidanceState.fingers.isEmpty)
            Center(
              child: FingerprintOverlay(
                width:         overlayW,
                height:        overlayH,
                isScanning:    _screenState == _ScreenState.capturing ||
                               _screenState == _ScreenState.checking,
                isHandCapture: widget.isHandCapture,
                liveQuality:   _liveQuality,
              ),
            ),

          // Per-finger tracked guidance boxes (four-finger capture, Android).
          if (_guidance != null && _screenState == _ScreenState.ready)
            FingerGuidanceOverlay(
              state: _guidanceState,
              previewSize: _controller!.value.previewSize ?? Size.zero,
              sensorOrientation: _controller!.description.sensorOrientation,
            ),

          // Instruction / status strip
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: _InstructionBanner(
              screenState:    _screenState,
              capturedCount:  _capturedCount,
              frameTarget:    _frameTarget,
              fingerLabel:    widget.fingerLabel,
              isHandCapture:  widget.isHandCapture,
              guidanceStatus: _guidance != null ? _guidanceState.status : null,
            ),
          ),

          // Flash effect while capturing
          if (_screenState == _ScreenState.capturing)
            Container(color: Colors.white.withValues(alpha: 0.06)),
        ],
      );
    });
  }

  Widget _buildBottomBar() {
    switch (_screenState) {
      case _ScreenState.ready:
        return _ReadyBar(
          onScan:            _autoTriggerEnabled ? null : _startCapture,
          onCancel:          () => Navigator.pop(context, null),
          autoTriggerActive: _autoTriggerEnabled,
        );

      case _ScreenState.capturing:
        return _ProgressBar(
          capturedCount: _capturedCount,
          frameTarget:   _frameTarget,
        );

      case _ScreenState.checking:
        return const _CheckingBar();

      case _ScreenState.success:
        return const _SuccessBar();

      case _ScreenState.failed:
        return _FailedBar(
          message:          _errorMessage,
          meanDisplacement: _meanDisplacement,
          onRetry:          _retry,
          onCancel:         () => Navigator.pop(context, null),
        );

      default:
        return const SizedBox(height: 80);
    }
  }
}

// ── Bottom-bar widgets ────────────────────────────────────────────────────────

class _ReadyBar extends StatelessWidget {
  /// null when auto-trigger is active — hides the manual Scan button.
  final VoidCallback? onScan;
  final VoidCallback onCancel;
  final bool autoTriggerActive;

  const _ReadyBar({
    required this.onScan,
    required this.onCancel,
    this.autoTriggerActive = false,
  });

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
          if (!autoTriggerActive) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.fingerprint, size: 20),
                label: const Text('Scan',
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
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int capturedCount;
  final int frameTarget;
  const _ProgressBar(
      {required this.capturedCount, required this.frameTarget});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: capturedCount / frameTarget,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 10),
          Text(
            'Hold still… capturing $capturedCount / $frameTarget',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CheckingBar extends StatelessWidget {
  const _CheckingBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Checking liveness…',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SuccessBar extends StatelessWidget {
  const _SuccessBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          SizedBox(width: 10),
          Text('Good Scan',
              style: TextStyle(
                  color: AppColors.success,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FailedBar extends StatelessWidget {
  final String? message;
  final double? meanDisplacement;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _FailedBar({
    required this.message,
    required this.meanDisplacement,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message ?? 'Liveness check failed.',
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13, height: 1.4),
                ),
              ),
            ]),
          ),
          if (meanDisplacement != null) ...[
            const SizedBox(height: 6),
            Text(
              'Detected movement: ${meanDisplacement!.toStringAsFixed(2)} px',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          const SizedBox(height: 14),
          Row(
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
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
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
        ],
      ),
    );
  }
}

// ── Instruction banner ────────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  final _ScreenState screenState;
  final int capturedCount;
  final int frameTarget;
  final String? fingerLabel;
  final bool isHandCapture;

  /// Live hand-tracking verdict — null when guidance is unavailable.
  final GuidanceStatus? guidanceStatus;

  const _InstructionBanner({
    required this.screenState,
    required this.capturedCount,
    required this.frameTarget,
    required this.fingerLabel,
    required this.isHandCapture,
    this.guidanceStatus,
  });

  @override
  Widget build(BuildContext context) {
    final (String main, String? sub) = switch (screenState) {
      _ScreenState.capturing => (
          'Hold still…',
          null,
        ),
      _ScreenState.checking => (
          'Analysing movement…',
          null,
        ),
      _ScreenState.success => (
          'Good Scan ✓',
          null,
        ),
      _ScreenState.failed => (
          'Liveness check failed',
          'Tap "Try Again" below',
        ),
      _ when guidanceStatus != null => switch (guidanceStatus!) {
          GuidanceStatus.searching => (
              'Show your four fingers to the camera',
              'Hold your hand flat, palm facing the lens',
            ),
          GuidanceStatus.tooFar => (
              'Move your hand closer',
              'The boxes should cover your fingertips',
            ),
          GuidanceStatus.holdStill => (
              'Hold still…',
              'Keep your fingers steady',
            ),
          GuidanceStatus.ready => (
              'Ready — scanning…',
              null,
            ),
        },
      _ => (
          isHandCapture
              ? 'Place hand flat · Fingers spread · Fill the frame'
              : 'Place finger inside the frame',
          'Hold steady — will scan automatically when ready',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (fingerLabel != null && screenState == _ScreenState.ready) ...[
          Text(fingerLabel!,
              style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          const SizedBox(height: 3),
        ],
        Text(main,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11)),
        ],
      ]),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white54),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                side: const BorderSide(color: Colors.white38)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      ),
    );
  }
}
