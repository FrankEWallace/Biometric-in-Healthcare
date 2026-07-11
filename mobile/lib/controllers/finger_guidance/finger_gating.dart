import 'dart:ui';

import 'finger_guidance_state.dart';

/// Shared capture-readiness gating for the four-finger overlay.
///
/// Both the Android (MediaPipe plugin) and iOS (native MethodChannel) guidance
/// controllers feed the same 21 hand landmarks here so the distance + stability
/// gates — and therefore the auto-capture behaviour — are identical on both
/// platforms. Keeping this in one place is what guarantees "boxes appear, then
/// capture fires only when four fingers are located and held still".
class HandGating {
  // MediaPipe hand-landmark indices: (DIP joint, fingertip) per finger, thumb
  // excluded — the four-finger capture uses index/middle/ring/little.
  static const _fingerJoints = [(7, 8), (11, 12), (15, 16), (19, 20)];

  // Distance gate: mean tip→DIP length (normalized). Below → hand too far for
  // usable ridge detail. Stability gate: mean fingertip displacement per
  // processed frame; must stay under [_maxJitter] for [_stableFor] before ready.
  static const _minFingerLength = 0.045;
  static const _maxJitter = 0.015;
  static const _stableFor = Duration(milliseconds: 500);

  List<Offset>? _prevTips;
  DateTime? _stableSince;

  void reset() {
    _prevTips = null;
    _stableSince = null;
  }

  /// Evaluate one frame's [landmarks] (21 normalized, unrotated-sensor points).
  /// Fewer than 21 points means no hand → [GuidanceStatus.searching].
  FingerGuidanceState evaluate(List<Offset> landmarks) {
    if (landmarks.length < 21) {
      reset();
      return FingerGuidanceState.searching;
    }

    final fingers = [
      for (final (dip, tip) in _fingerJoints)
        FingerTipRegion(tip: landmarks[tip], dip: landmarks[dip]),
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
      return FingerGuidanceState(
          status: GuidanceStatus.tooFar, fingers: fingers);
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

    final stable =
        _stableSince != null && now.difference(_stableSince!) >= _stableFor;
    return FingerGuidanceState(
      status: stable ? GuidanceStatus.ready : GuidanceStatus.holdStill,
      fingers: fingers,
    );
  }
}
