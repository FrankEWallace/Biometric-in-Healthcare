import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessStep { idle, promptBlink, promptTurn, capturing, passed, failed }

/// Active liveness state machine: blink → head-turn → captured.
///
/// Call [start] to begin. Feed each camera frame through [processFaces].
/// Listen for state changes via [ChangeNotifier]. When [isPassed] becomes true,
/// the host screen should stop the image stream and call takePicture().
class LivenessController extends ChangeNotifier {
  LivenessStep _step = LivenessStep.idle;
  String _instruction = 'Center your face in the oval';
  String? _subInstruction;

  // Blink detection
  int _blinkFrameCount = 0;
  static const int _blinkFramesRequired = 2;
  static const double _eyeClosedThreshold = 0.25;

  // Turn detection
  double? _baselineYaw;
  static const double _turnThreshold = 15.0;

  // Per-step timeout
  Timer? _stepTimer;
  static const Duration _stepTimeout = Duration(seconds: 5);

  LivenessStep get step => _step;
  String get instruction => _instruction;
  String? get subInstruction => _subInstruction;
  bool get isPassed => _step == LivenessStep.passed;
  bool get isFailed => _step == LivenessStep.failed;

  /// Begin the liveness sequence. Must be called after the camera is ready.
  void start() {
    _cancelTimer();
    _step = LivenessStep.promptBlink;
    _instruction = 'Blink your eyes';
    _subInstruction = 'Close both eyes briefly';
    _blinkFrameCount = 0;
    _startTimer();
    notifyListeners();
  }

  /// Feed ML Kit [faces] for the current camera frame.
  /// Call this from the image stream; ignores frames when not in an active step.
  void processFaces(List<Face> faces) {
    if (_step != LivenessStep.promptBlink && _step != LivenessStep.promptTurn) {
      return;
    }
    if (faces.isEmpty) return;

    // Use the largest detected face.
    final face = faces.reduce(
      (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
    );

    if (_step == LivenessStep.promptBlink) {
      _checkBlink(face);
    } else {
      _checkTurn(face);
    }
  }

  void _checkBlink(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;

    if (left != null &&
        right != null &&
        left < _eyeClosedThreshold &&
        right < _eyeClosedThreshold) {
      _blinkFrameCount++;
      if (_blinkFrameCount >= _blinkFramesRequired) {
        _advanceToTurn();
      }
    } else {
      _blinkFrameCount = 0;
    }
  }

  void _checkTurn(Face face) {
    final yaw = face.headEulerAngleY;
    if (yaw == null) return;

    _baselineYaw ??= yaw;
    if ((yaw - _baselineYaw!).abs() > _turnThreshold) {
      _pass();
    }
  }

  void _advanceToTurn() {
    _cancelTimer();
    _blinkFrameCount = 0;
    _baselineYaw = null;
    _step = LivenessStep.promptTurn;
    _instruction = 'Slowly turn your head';
    _subInstruction = 'Turn left or right';
    _startTimer();
    notifyListeners();
  }

  void _pass() {
    _cancelTimer();
    _step = LivenessStep.passed;
    _instruction = 'Liveness confirmed';
    _subInstruction = null;
    notifyListeners();
  }

  void _startTimer() {
    _stepTimer = Timer(_stepTimeout, _onTimeout);
  }

  void _cancelTimer() {
    _stepTimer?.cancel();
    _stepTimer = null;
  }

  void _onTimeout() {
    if (_step == LivenessStep.passed || _step == LivenessStep.failed) return;
    _step = LivenessStep.failed;
    _instruction = 'Check timed out';
    _subInstruction = 'Please try again';
    notifyListeners();
  }

  /// Reset back to idle so the screen can retry.
  void reset() {
    _cancelTimer();
    _step = LivenessStep.idle;
    _blinkFrameCount = 0;
    _baselineYaw = null;
    _instruction = 'Center your face in the oval';
    _subInstruction = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}
