import 'dart:ui';

/// Capture-readiness verdict for the four-finger guidance overlay.
///
/// Maps to the standard contactless-capture UX colors:
///   searching  → no hand detected (frame stays neutral/red)
///   tooFar     → fingers detected but too small in frame (amber, "move closer")
///   holdStill  → fingers close enough but still moving (amber)
///   ready      → stable + close enough; auto-capture may fire (green)
enum GuidanceStatus { searching, tooFar, holdStill, ready }

/// One tracked fingertip: the tip and DIP-joint landmarks in *normalized
/// sensor coordinates* (0.0–1.0, unrotated camera frame). The fingerprint pad
/// lies between the two points; the overlay draws its box there.
class FingerTipRegion {
  final Offset tip;
  final Offset dip;

  const FingerTipRegion({required this.tip, required this.dip});
}

/// Snapshot of guidance for one processed frame.
class FingerGuidanceState {
  final GuidanceStatus status;

  /// Index, middle, ring, little fingertip regions — empty while searching.
  final List<FingerTipRegion> fingers;

  const FingerGuidanceState({required this.status, this.fingers = const []});

  static const searching = FingerGuidanceState(status: GuidanceStatus.searching);

  bool get isReady => status == GuidanceStatus.ready;
}
