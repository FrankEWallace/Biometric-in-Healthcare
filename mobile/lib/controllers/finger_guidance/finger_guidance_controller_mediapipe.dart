import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'finger_gating.dart';
import 'finger_guidance_controller.dart';

/// Android → MediaPipe Hand Landmarker via the `hand_landmarker` JNI plugin.
/// iOS → MediaPipe via the native [HandLandmarkerBridge] MethodChannel.
/// Anything else (should not reach here off-ffi) falls back to null.
FingerGuidanceController? createFingerGuidance() {
  if (Platform.isAndroid) {
    try {
      return _MediaPipeFingerGuidance();
    } catch (_) {
      // Native init failed (old device, missing GPU delegate, …) — fall back.
      return null;
    }
  }
  if (Platform.isIOS) {
    return _IosFingerGuidance();
  }
  return null;
}

// ── Android: hand_landmarker JNI plugin ─────────────────────────────────────

class _MediaPipeFingerGuidance implements FingerGuidanceController {
  _MediaPipeFingerGuidance()
      : _plugin = HandLandmarkerPlugin.create(
          numHands: 1,
          minHandDetectionConfidence: 0.6,
        );

  final HandLandmarkerPlugin _plugin;
  final _states = StreamController<FingerGuidanceState>.broadcast();
  final _gating = HandGating();

  DateTime _lastFed = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _detecting = false;

  // ~10 fps is enough for responsive guidance without saturating the device.
  static const _feedInterval = Duration(milliseconds: 100);

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
    if (_disposed) return;

    final landmarks = hands.isEmpty
        ? const <Offset>[]
        : [for (final lm in hands.first.landmarks) Offset(lm.x, lm.y)];
    _states.add(_gating.evaluate(landmarks));
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

// ── iOS: MediaPipe via native MethodChannel ─────────────────────────────────

class _IosFingerGuidance implements FingerGuidanceController {
  static const _channel = MethodChannel('bih/hand_landmarker');

  final _states = StreamController<FingerGuidanceState>.broadcast();
  final _gating = HandGating();

  DateTime _lastFed = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _detecting = false;

  // If the native detector can't initialize, degrade to the sharpness-only
  // trigger (same behaviour as no guidance at all) rather than blocking capture:
  // emit a ready state with no finger boxes so the caller's auto-trigger fires.
  bool _nativeUnavailable = false;

  static const _feedInterval = Duration(milliseconds: 100);

  @override
  Stream<FingerGuidanceState> get stream => _states.stream;

  @override
  void processFrame(CameraImage image, int sensorOrientation) {
    if (_disposed || _detecting) return;
    if (_nativeUnavailable) return;
    // iOS delivers a single BGRA8888 plane (set by the capture screen).
    if (image.planes.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastFed) < _feedInterval) return;
    _lastFed = now;

    _detecting = true;
    _detect(image).whenComplete(() => _detecting = false);
  }

  Future<void> _detect(CameraImage image) async {
    final plane = image.planes.first;
    try {
      final result = await _channel.invokeMethod<List<Object?>>('detect', {
        'bytes': plane.bytes,
        'width': image.width,
        'height': image.height,
        'bytesPerRow': plane.bytesPerRow,
      });
      if (_disposed) return;

      final flat = result ?? const <Object?>[];
      final landmarks = <Offset>[
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
      ];
      _states.add(_gating.evaluate(landmarks));
    } on PlatformException {
      // Native detector unavailable — fall back to sharpness-only capture.
      _nativeUnavailable = true;
      if (!_disposed) {
        _states.add(
            const FingerGuidanceState(status: GuidanceStatus.ready, fingers: []));
      }
    } catch (_) {
      // Transient frame error — just wait for the next frame.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _states.close();
  }
}
