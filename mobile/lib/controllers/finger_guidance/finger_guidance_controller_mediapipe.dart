import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'finger_guidance_controller.dart';

/// Android: MediaPipe Hand Landmarker. Other ffi platforms (iOS) have no
/// native implementation, so return null and let callers fall back.
FingerGuidanceController? createFingerGuidance() {
  if (!Platform.isAndroid) return null;
  try {
    return _MediaPipeFingerGuidance();
  } catch (_) {
    // Native init failed (old device, missing GPU delegate, …) — fall back.
    return null;
  }
}

class _MediaPipeFingerGuidance implements FingerGuidanceController {
  _MediaPipeFingerGuidance()
      : _plugin = HandLandmarkerPlugin.create(
          numHands: 1,
          minHandDetectionConfidence: 0.6,
        );

  final HandLandmarkerPlugin _plugin;
  final _states = StreamController<FingerGuidanceState>.broadcast();

  DateTime _lastFed = DateTime.fromMillisecondsSinceEpoch(0);
  List<Offset>? _prevTips;
  DateTime? _stableSince;
  bool _disposed = false;
  bool _detecting = false;

  // MediaPipe hand-landmark indices: (DIP joint, fingertip) per finger,
  // thumb excluded — the four-finger capture uses index/middle/ring/little.
  static const _fingerJoints = [(7, 8), (11, 12), (15, 16), (19, 20)];

  // ~10 fps is enough for responsive guidance without saturating the device.
  static const _feedInterval = Duration(milliseconds: 100);

  // Distance gate: mean tip→DIP length (normalized). Below → hand too far
  // for usable ridge detail. Stability gate: mean fingertip displacement per
  // processed frame; must stay under _maxJitter for _stableFor before ready.
  static const _minFingerLength = 0.045;
  static const _maxJitter = 0.015;
  static const _stableFor = Duration(milliseconds: 500);

  @override
  Stream<FingerGuidanceState> get stream => _states.stream;

  @override
  void processFrame(CameraImage image, int sensorOrientation) {
    if (_disposed || _detecting) return;
    // detect() needs the three YUV420 planes; skip other stream formats.
    if (image.planes.length < 3) return;
    final now = DateTime.now();
    if (now.difference(_lastFed) < _feedInterval) return;
    _lastFed = now;

    _detecting = true;
    List<Hand> hands;
    try {
      hands = _plugin.detect(image, sensorOrientation);
    } catch (_) {
      // A dropped frame just delays the next state update.
      _detecting = false;
      return;
    }
    _detecting = false;
    _onHands(hands);
  }

  void _onHands(List<Hand> hands) {
    if (_disposed) return;

    if (hands.isEmpty || hands.first.landmarks.length < 21) {
      _prevTips = null;
      _stableSince = null;
      _states.add(FingerGuidanceState.searching);
      return;
    }

    final lm = hands.first.landmarks;
    final fingers = [
      for (final (dip, tip) in _fingerJoints)
        FingerTipRegion(
          tip: Offset(lm[tip].x, lm[tip].y),
          dip: Offset(lm[dip].x, lm[dip].y),
        ),
    ];
    final tips = [for (final f in fingers) f.tip];

    // Distance gate.
    final meanLength = fingers
            .map((f) => (f.tip - f.dip).distance)
            .reduce((a, b) => a + b) /
        fingers.length;
    if (meanLength < _minFingerLength) {
      _prevTips = tips;
      _stableSince = null;
      _states.add(
          FingerGuidanceState(status: GuidanceStatus.tooFar, fingers: fingers));
      return;
    }

    // Stability gate.
    final prev = _prevTips;
    _prevTips = tips;
    double jitter = 0;
    if (prev != null && prev.length == tips.length) {
      for (var i = 0; i < tips.length; i++) {
        jitter += (tips[i] - prev[i]).distance;
      }
      jitter /= tips.length;
    } else {
      jitter = double.infinity;
    }

    final now = DateTime.now();
    if (jitter > _maxJitter) {
      _stableSince = null;
    } else {
      _stableSince ??= now;
    }

    final stable = _stableSince != null &&
        now.difference(_stableSince!) >= _stableFor;
    _states.add(FingerGuidanceState(
      status: stable ? GuidanceStatus.ready : GuidanceStatus.holdStill,
      fingers: fingers,
    ));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _states.close();
    try {
      _plugin.dispose();
    } catch (_) {}
  }
}
