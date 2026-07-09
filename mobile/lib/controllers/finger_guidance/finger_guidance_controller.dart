import 'package:camera/camera.dart';

import 'finger_guidance_state.dart';
// Web has no dart:ffi, so it gets the no-op stub; Android/iOS compile the
// MediaPipe implementation, which returns null at runtime off-Android.
import 'finger_guidance_controller_stub.dart'
    if (dart.library.ffi) 'finger_guidance_controller_mediapipe.dart' as impl;

export 'finger_guidance_state.dart';

/// Real-time four-finger detection driving the capture guidance overlay.
///
/// Backed by MediaPipe Hand Landmarker on Android. [create] returns `null`
/// on platforms without support (iOS/web) or if the native engine fails to
/// initialize — callers fall back to the sharpness-only auto-trigger.
abstract class FingerGuidanceController {
  /// Returns a controller, or `null` when hand tracking is unavailable.
  static FingerGuidanceController? create() => impl.createFingerGuidance();

  /// Emits one [FingerGuidanceState] per processed frame.
  Stream<FingerGuidanceState> get stream;

  /// Feed a camera stream frame (YUV420). Throttled internally to ~10 fps;
  /// safe to call for every frame.
  void processFrame(CameraImage image, int sensorOrientation);

  /// Releases native resources.
  void dispose();
}
