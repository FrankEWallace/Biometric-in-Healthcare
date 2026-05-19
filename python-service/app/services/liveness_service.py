"""
Passive liveness detection algorithms — server-side checks that run on
still images (face) or short frame sequences (fingerprint).

These complement the Flutter active liveness (blink + head-turn) and do
not replace it.  Both checks must pass before a biometric is accepted.

Face checks
-----------
  moire_score     — FFT-based screen/printer dot-pattern detector.
                    Screens and inkjet prints introduce periodic high-frequency
                    bands in the Fourier domain that live skin does not produce.
                    Score > MOIRE_THRESHOLD → likely spoofed.

  highlight_ratio — Specular-highlight ratio.
                    Real skin reflects a small, localised specular highlight
                    (corneas, nose tip, forehead).  Flat printed surfaces lack
                    highlights almost entirely; phone screens produce broad
                    overexposed regions.
                    ratio < HIGHLIGHT_MIN or > HIGHLIGHT_MAX → suspicious.

Fingerprint check
-----------------
  mean_displacement — Lucas-Kanade sparse optical flow over consecutive frame
                      pairs.  A live finger pressed against the camera shows
                      micro-movement (0.3–2.5 px) from breathing / pulse.
                      A photo or screen shows near-zero displacement.

Threshold notes
---------------
  All numeric thresholds are initial engineering estimates calibrated on a
  small sample set.  They MUST be validated via a proper FAR / FRR study
  with real patients before production deployment.
"""
from __future__ import annotations

import cv2
import numpy as np

# ── Thresholds (tune via FAR/FRR study before production) ────────────────────

MOIRE_THRESHOLD   = 25.0   # screen_score above this → moiré attack
HIGHLIGHT_MIN     = 0.001  # below this → flat/matte surface (print)
HIGHLIGHT_MAX     = 0.12   # above this → overexposed region (phone screen)
FLOW_LIVE_MIN     = 0.15   # mean displacement below this → static (spoofed)
SKIN_MIN_RATIO    = 0.08   # skin-tone pixels below this fraction → no hand in frame


# ── Face passive liveness ─────────────────────────────────────────────────────

def face_liveness_check(image_bgr: np.ndarray) -> dict:
    """
    Run both passive checks on a single BGR face image.

    Returns
    -------
    {
        "is_live":          bool,
        "screen_score":     float,   # higher = more likely screen/print
        "highlight_ratio":  float,   # fraction of near-white pixels
        "reason":           str,     # "ok" | "moire_detected" | "no_highlights"
                                     # | "excess_highlights" | "moire_and_highlights"
    }
    """
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    screen_score    = _moire_score(gray)
    highlight_ratio = _highlight_ratio(image_bgr)

    moire_flag     = screen_score    >  MOIRE_THRESHOLD
    low_hl_flag    = highlight_ratio <  HIGHLIGHT_MIN
    high_hl_flag   = highlight_ratio >  HIGHLIGHT_MAX

    if moire_flag and (low_hl_flag or high_hl_flag):
        reason = "moire_and_highlights"
    elif moire_flag:
        reason = "moire_detected"
    elif low_hl_flag:
        reason = "no_highlights"
    elif high_hl_flag:
        reason = "excess_highlights"
    else:
        reason = "ok"

    return {
        "is_live":         not (moire_flag or low_hl_flag or high_hl_flag),
        "screen_score":    round(screen_score, 2),
        "highlight_ratio": round(highlight_ratio, 6),
        "reason":          reason,
    }


def _moire_score(gray: np.ndarray) -> float:
    """
    Coefficient-of-variation of the log-magnitude FFT spectrum in the
    mid-frequency ring (radii 20–100 px on a 256×256 canvas).

    Screen / printer dot-grids produce sharp, isolated peaks in this band →
    high standard deviation relative to mean → high CV score.
    Real skin has a smooth, broadband spectrum → low CV.

    Score is multiplied by 10 so it spans a 0–100-ish range.
    """
    resized   = cv2.resize(gray, (256, 256)).astype(np.float32)
    spectrum  = np.abs(np.fft.fftshift(np.fft.fft2(resized)))

    h, w  = spectrum.shape
    cy, cx = h // 2, w // 2

    # Zero DC component and immediate surroundings
    spectrum[cy - 12:cy + 12, cx - 12:cx + 12] = 0

    # Log scale for better dynamic range
    log_spec = np.log1p(spectrum)

    # Annular mid-frequency ring
    y_idx, x_idx = np.mgrid[:h, :w]
    dist = np.sqrt((y_idx - cy) ** 2 + (x_idx - cx) ** 2)
    ring  = log_spec[(dist >= 20) & (dist <= 100)]

    mean_val = float(ring.mean())
    if mean_val < 1e-9:
        return 0.0

    cv_score = float(ring.std() / mean_val) * 10
    return round(cv_score, 2)


def _highlight_ratio(image_bgr: np.ndarray) -> float:
    """
    Fraction of near-white pixels (> 240 in all three BGR channels).

    Real skin: small specular spot → ratio typically 0.001–0.04.
    Flat print: almost no highlights → ratio < 0.001.
    Phone screen in frame: broad overexposed area → ratio > 0.12.
    """
    # Near-white: all channels above 240
    near_white = np.all(image_bgr > 240, axis=2)
    total      = image_bgr.shape[0] * image_bgr.shape[1]
    ratio      = float(near_white.sum()) / total
    return round(ratio, 6)


# ── Hand presence detection ───────────────────────────────────────────────────

def detect_hand_presence(frame: np.ndarray) -> bool:
    """
    Returns True when a hand-like skin-tone region covers at least
    SKIN_MIN_RATIO of the frame area.

    Uses HSV skin-tone segmentation — fast, no model required.
    Two hue ranges cover most human complexions under indoor lighting:
      Range 1: H 0–25   (warm skin tones, light to medium)
      Range 2: H 160–180 (wrap-around at red end, darker complexions)

    A morphological open (5×5 ellipse) removes isolated noise pixels so
    the ratio is not inflated by stray warm-coloured objects.
    """
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

    mask = cv2.bitwise_or(
        cv2.inRange(hsv, np.array([0,   20,  50], dtype=np.uint8),
                         np.array([25, 200, 255], dtype=np.uint8)),
        cv2.inRange(hsv, np.array([160,  20,  50], dtype=np.uint8),
                         np.array([180, 200, 255], dtype=np.uint8)),
    )

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask   = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

    skin_ratio = float(cv2.countNonZero(mask)) / (frame.shape[0] * frame.shape[1])
    return skin_ratio >= SKIN_MIN_RATIO


# ── Fingerprint passive liveness ──────────────────────────────────────────────

def fingerprint_liveness_check(frames: list[np.ndarray]) -> dict:
    """
    Detect micro-movement across consecutive camera frames via sparse optical
    flow (Lucas-Kanade).

    A live finger pressed against the camera lens shows 0.3–2.5 px mean
    displacement between frames caused by breathing and pulse.  A printed
    image or phone screen shows near-zero displacement.

    Parameters
    ----------
    frames : list of BGR (or grayscale) numpy arrays, ordered oldest → newest.
             At least 2 frames required; 6–10 recommended.

    Returns
    -------
    {
        "is_live":           bool,
        "mean_displacement": float,  # average px movement per frame pair
        "frame_count":       int,
        "reason":            str,    # "ok" | "static_image" | "insufficient_frames"
                                     # | "no_features"
    }
    """
    n = len(frames)

    if n < 2:
        return {
            "is_live":           False,
            "mean_displacement": 0.0,
            "frame_count":       n,
            "reason":            "insufficient_frames",
        }

    # A2: Reject before running optical flow if no hand is visible in frame.
    if not detect_hand_presence(frames[0]):
        return {
            "is_live":           False,
            "mean_displacement": 0.0,
            "frame_count":       n,
            "reason":            "no_hand",
        }

    displacements: list[float] = []

    for i in range(n - 1):
        prev_gray = _to_gray(frames[i])
        curr_gray = _to_gray(frames[i + 1])

        pts = cv2.goodFeaturesToTrack(
            prev_gray,
            maxCorners=150,
            qualityLevel=0.01,
            minDistance=5,
            blockSize=7,
        )
        if pts is None or len(pts) < 5:
            continue

        next_pts, status, _ = cv2.calcOpticalFlowPyrLK(
            prev_gray, curr_gray, pts, None,
            winSize=(15, 15),
            maxLevel=2,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 10, 0.03),
        )

        if next_pts is None:
            continue

        good = status.ravel() == 1
        if not np.any(good):
            continue

        diff  = (next_pts[good] - pts[good]).reshape(-1, 2)
        dists = np.linalg.norm(diff, axis=1)
        displacements.append(float(dists.mean()))

    if not displacements:
        return {
            "is_live":           False,
            "mean_displacement": 0.0,
            "frame_count":       n,
            "reason":            "no_features",
        }

    mean_disp = round(float(np.mean(displacements)), 4)
    is_live   = mean_disp >= FLOW_LIVE_MIN

    return {
        "is_live":           is_live,
        "mean_displacement": mean_disp,
        "frame_count":       n,
        "reason":            "ok" if is_live else "static_image",
    }


def _to_gray(img: np.ndarray) -> np.ndarray:
    if img.ndim == 2:
        return img
    return cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
