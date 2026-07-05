"""
Four-finger hand segmentation (Phase 1).

Goal: a nurse photographs a hand (four fingers raised, palm/back toward the
camera on a contrasting background); this module returns up to four clean
per-finger crops in the RidgeBase-contactless crop format, so the downstream
matcher and calibration harness keep working on the same shape of input.

Approach (classical, dependency-light, offline)
-----------------------------------------------
1. Skin/foreground mask — YCrCb skin thresholding ∩ Otsu, largest contour.
2. Fingertip localisation — convex hull + convexity defects: the valleys
   between raised fingers are the deep defect points; the hull vertices above
   them are the fingertips. Falls back to vertical-extrema peaks along the top
   of the contour if defect analysis is degenerate.
3. Crop — a finger-width box running from each fingertip down the finger axis.

Why classical (not MediaPipe): MediaPipe Hands would be more robust but is not
installed and, architecturally, hand-landmark detection belongs **on-device**
in the Flutter capture screen (lower latency, no image upload for framing).
This server-side module is the functionality-first MVP + fallback so the whole
four-finger pipeline runs end-to-end today; it can be swapped for on-device
landmarks without touching the matcher or endpoints.

Limitation: robustness across skin tones / lighting / backgrounds needs real
whole-hand captures to validate (RidgeBase ships *pre-segmented* crops, not hand
photos). The unit test drives a synthetic hand silhouette to lock the geometry.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

# Ordered index → little (thumb excluded: IDEMIA 4F slap convention).
_RIGHT = ("right_index", "right_middle", "right_ring", "right_little")
_LEFT = ("left_index", "left_middle", "left_ring", "left_little")


@dataclass
class FingerCrop:
    """One segmented finger: its crop plus where it came from."""

    image: np.ndarray  # BGR crop, ready for Matcher.extract()
    tip: tuple[int, int]  # fingertip (x, y) in the source image
    bbox: tuple[int, int, int, int]  # x, y, w, h in the source image
    order: int  # left-to-right index in the photo (0-based)
    finger_position: str | None = None  # assigned once hand/orientation known


class SegmentationError(RuntimeError):
    """Raised when a hand / four fingers cannot be located."""


# ---------------------------------------------------------------------------
# Masking
# ---------------------------------------------------------------------------

def _skin_mask(image_bgr: np.ndarray) -> np.ndarray:
    """Binary foreground mask combining YCrCb skin range with Otsu."""
    ycrcb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2YCrCb)
    # Broad skin band in Cr/Cb — tolerant across skin tones.
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    _, otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    # Union catches skin the Otsu split misses and vice versa; then clean up.
    mask = cv2.bitwise_or(skin, otsu)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    return mask


def _largest_contour(mask: np.ndarray) -> np.ndarray:
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        raise SegmentationError("no foreground contour found — check framing/contrast")
    return max(contours, key=cv2.contourArea)


# ---------------------------------------------------------------------------
# Fingertip localisation
# ---------------------------------------------------------------------------

def _fingertips_from_defects(contour: np.ndarray, want: int = 4) -> list[tuple[int, int]]:
    """
    Fingertips via convex-hull + convexity-defect valleys.

    The far points of the deepest defects are the valleys between fingers; the
    hull points straddling each valley are fingertips. Return the ``want``
    top-most hull points (smallest y = highest = tips of raised fingers).
    """
    hull_idx = cv2.convexHull(contour, returnPoints=False)
    tips: list[tuple[int, int]] = []
    if hull_idx is not None and len(hull_idx) > 3:
        defects = cv2.convexityDefects(contour, hull_idx)
        if defects is not None and len(defects) >= want - 1:
            # Candidate tips = hull vertices; rank by height (topmost first).
            hull_pts = [tuple(contour[i][0]) for i in hull_idx.ravel()]
            hull_pts = sorted(hull_pts, key=lambda p: p[1])  # ascending y
            tips = _dedupe_close(hull_pts, want)
    return tips


def _fingertips_from_extrema(contour: np.ndarray, want: int = 4) -> list[tuple[int, int]]:
    """
    Fallback: the topmost contour points, spread horizontally into ``want``
    columns, one peak per column. Assumes fingers point up.
    """
    pts = contour.reshape(-1, 2)
    x_min, x_max = pts[:, 0].min(), pts[:, 0].max()
    span = max(1, x_max - x_min)
    peaks: list[tuple[int, int]] = []
    for i in range(want):
        lo = x_min + span * i // want
        hi = x_min + span * (i + 1) // want
        col = pts[(pts[:, 0] >= lo) & (pts[:, 0] < hi)]
        if len(col):
            top = col[col[:, 1].argmin()]
            peaks.append((int(top[0]), int(top[1])))
    return peaks


def _dedupe_close(points: list[tuple[int, int]], want: int, min_dx: int = 20) -> list[tuple[int, int]]:
    """Keep the topmost points, dropping ones too close horizontally."""
    kept: list[tuple[int, int]] = []
    for p in points:
        if all(abs(p[0] - q[0]) > min_dx for q in kept):
            kept.append(p)
        if len(kept) == want:
            break
    return kept


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def assign_finger_positions(n: int, hand: str, order_ltr: bool = True) -> list[str]:
    """
    Map ``n`` left-to-right crops to anatomical finger positions.

    Orientation assumption (documented, caller may override by pre-ordering):
    fingers pointing up, palm facing the camera. For a RIGHT hand the thumb is
    on the left, so left→right reads index→little; for a LEFT hand the thumb is
    on the right, so left→right reads little→index. ``order_ltr=False`` if the
    source crops are already ordered right-to-left.
    """
    if hand.lower().startswith("r"):
        seq = list(_RIGHT)             # left→right: index, middle, ring, little
    else:
        seq = list(reversed(_LEFT))    # left→right: little, ring, middle, index
    if not order_ltr:
        seq = list(reversed(seq))
    return seq[:n]


def segment_hand(
    image_bgr: np.ndarray,
    *,
    hand: str = "right",
    want: int = 4,
    crop_aspect: float = 2.2,
) -> list[FingerCrop]:
    """
    Segment a whole-hand photo into up to ``want`` per-finger crops.

    Returns crops ordered left-to-right, each tagged with a ``finger_position``
    under the orientation assumption in ``assign_finger_positions``. Raises
    ``SegmentationError`` if fewer than ``want`` fingers can be located.
    """
    if image_bgr is None or image_bgr.size == 0:
        raise SegmentationError("empty image")

    mask = _skin_mask(image_bgr)
    contour = _largest_contour(mask)

    # Column-extrema is the robust primary for the fingers-up framing (one tip
    # per horizontal band). Convex-hull defects are the fallback for tilted or
    # unevenly-spaced hands where fixed columns split/merge fingers.
    tips = _fingertips_from_extrema(contour, want)
    if len(tips) < want:
        tips = _fingertips_from_defects(contour, want)
    if len(tips) < want:
        raise SegmentationError(
            f"located {len(tips)}/{want} fingertips — reshoot with fingers "
            "separated against a plain background"
        )

    tips = sorted(tips, key=lambda p: p[0])[:want]  # left-to-right

    # Estimate finger width from tip spacing; crop a box down each finger axis.
    xs = [t[0] for t in tips]
    spacing = np.median(np.diff(sorted(xs))) if len(xs) > 1 else image_bgr.shape[1] // want
    fw = max(24, int(spacing * 0.8))
    fh = int(fw * crop_aspect)
    H, W = image_bgr.shape[:2]

    positions = assign_finger_positions(want, hand)
    crops: list[FingerCrop] = []
    for i, (tx, ty) in enumerate(tips):
        x0 = max(0, tx - fw // 2)
        y0 = max(0, ty)  # crop downward from the tip along the finger
        x1 = min(W, x0 + fw)
        y1 = min(H, y0 + fh)
        crop = image_bgr[y0:y1, x0:x1].copy()
        if crop.size == 0:
            continue
        crops.append(
            FingerCrop(
                image=crop,
                tip=(int(tx), int(ty)),
                bbox=(x0, y0, x1 - x0, y1 - y0),
                order=i,
                finger_position=positions[i] if i < len(positions) else None,
            )
        )

    if len(crops) < want:
        raise SegmentationError(f"produced {len(crops)}/{want} usable crops")
    return crops
