"""
ORB feature extraction and BFMatcher-based fingerprint matching.

Responsibilities:
  - Detect keypoints with ORB FAST detector
  - Compute BRIEF descriptors for each keypoint
  - Match two descriptor sets with BFMatcher + Lowe ratio test
  - Serialize results to JSON-safe structures
  - Handle low-quality / feature-sparse images without raising exceptions

This module operates on any uint8 grayscale or binary image.
It is intentionally decoupled from the preprocessing pipeline so that
either can be swapped or tested independently.

Typical usage:
    from app.services.feature_extractor import extract_features, match_features

    f1 = extract_features(image1)
    f2 = extract_features(image2)
    result = match_features(f1["descriptors"], f2["descriptors"])
    # result["score"]          → float  0.0–100.0
    # result["good_matches"]   → int
    # result["verdict"]        → "MATCH" | "NO MATCH"
"""

from __future__ import annotations

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_ORB_N_FEATURES = 500        # maximum keypoints ORB will return
_LOW_QUALITY_THRESHOLD = 10  # fewer keypoints than this → "low_quality" status

# Matching thresholds
_RATIO_TEST_THRESHOLD = 0.75  # Lowe ratio test — lower = stricter
_MATCH_SCORE_THRESHOLD = 20.0 # minimum score (0–100) to declare "MATCH"


# ---------------------------------------------------------------------------
# Step functions
# ---------------------------------------------------------------------------

def detect_keypoints(
    image: np.ndarray,
    n_features: int = _ORB_N_FEATURES,
) -> tuple[list[cv2.KeyPoint], cv2.ORB]:
    """
    Detect ORB keypoints on a grayscale or binary image.

    Args:
        image:      uint8 image (grayscale or binary, single channel).
        n_features: Maximum number of keypoints to retain. Default 500.

    Returns:
        (keypoints, orb_instance) — the ORB instance is returned so that
        ``compute_descriptors`` can reuse it without re-initialising.

    Raises:
        ValueError: If ``image`` is not a 2-D uint8 array.
    """
    if image.ndim != 2:
        raise ValueError(
            f"detect_keypoints expects a 2-D (grayscale) image, got shape {image.shape}."
        )
    if image.dtype != np.uint8:
        raise ValueError(
            f"detect_keypoints expects uint8 dtype, got {image.dtype}."
        )

    orb = cv2.ORB_create(nfeatures=n_features)
    keypoints = orb.detect(image, None)
    return keypoints, orb


def compute_descriptors(
    image: np.ndarray,
    keypoints: list[cv2.KeyPoint],
    orb: cv2.ORB,
) -> np.ndarray:
    """
    Compute BRIEF descriptors for the given keypoints.

    Args:
        image:     Same image passed to ``detect_keypoints``.
        keypoints: Keypoints returned by ``detect_keypoints``.
        orb:       The same ORB instance used for detection (preserves params).

    Returns:
        uint8 ndarray of shape (N, 32) where N = number of keypoints with
        valid descriptors.  Returns a (0, 32) empty array when no descriptors
        can be computed (e.g. blank / uniform image).
    """
    if not keypoints:
        return np.zeros((0, 32), dtype=np.uint8)

    _, descriptors = orb.compute(image, keypoints)

    if descriptors is None:
        return np.zeros((0, 32), dtype=np.uint8)

    return descriptors  # shape (N, 32), dtype uint8


# ---------------------------------------------------------------------------
# Serialization helpers
# ---------------------------------------------------------------------------

def _serialize_keypoints(keypoints: list[cv2.KeyPoint]) -> list[dict]:
    """
    Convert cv2.KeyPoint objects to JSON-serialisable dicts.

    Fields returned per keypoint:
      - pt      [x, y]   — sub-pixel location
      - size             — diameter of the meaningful neighbourhood
      - angle            — orientation in degrees [0, 360), -1 if undefined
      - response         — detector response strength (higher = more distinctive)
      - octave           — pyramid octave the keypoint was found in
      - class_id         — object class (−1 when unused)
    """
    return [
        {
            "pt": [round(kp.pt[0], 2), round(kp.pt[1], 2)],
            "size": round(kp.size, 2),
            "angle": round(kp.angle, 2),
            "response": round(kp.response, 6),
            "octave": kp.octave,
            "class_id": kp.class_id,
        }
        for kp in keypoints
    ]


def _serialize_descriptors(descriptors: np.ndarray) -> list[list[int]]:
    """
    Convert the (N, 32) uint8 descriptor matrix to a nested Python list.

    Each inner list is a 32-element row of uint8 values (0–255).
    This format is directly JSON-serialisable and can be reconstructed with:
        np.array(descriptors, dtype=np.uint8)
    """
    return descriptors.tolist()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def extract_features(
    image: np.ndarray,
    n_features: int = _ORB_N_FEATURES,
) -> dict:
    """
    Full ORB feature extraction pipeline: detect → describe → serialize.

    Designed to run on the output of ``preprocess_fingerprint`` (the
    binarized / thinned image), but accepts any uint8 grayscale image.

    Low-quality handling:
      - Blank image (all zeros / all white)  → returns empty descriptors,
        status "no_features".
      - Very few keypoints (< 10)            → returns what was found,
        status "low_quality".  Callers should reject or flag these results.
      - Normal result                        → status "ok".

    Args:
        image:      2-D uint8 grayscale or binary image.
        n_features: ORB feature budget. Default 500.

    Returns::

        {
            "keypoint_count": 312,
            "keypoints": [
                {"pt": [x, y], "size": …, "angle": …, "response": …,
                 "octave": …, "class_id": …},
                …
            ],
            "descriptors": [[int, …], …],   # shape (N, 32), values 0-255
            "status": "ok"                   # "ok" | "low_quality" | "no_features"
        }
    """
    # Ensure single-channel uint8
    if image.ndim == 3:
        image = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    if image.dtype != np.uint8:
        image = image.astype(np.uint8)

    keypoints, orb = detect_keypoints(image, n_features=n_features)
    descriptors    = compute_descriptors(image, keypoints, orb)

    n_kp = len(keypoints)

    if n_kp == 0 or descriptors.shape[0] == 0:
        status = "no_features"
    elif n_kp < _LOW_QUALITY_THRESHOLD:
        status = "low_quality"
    else:
        status = "ok"

    return {
        "keypoint_count": n_kp,
        "keypoints": _serialize_keypoints(keypoints),
        "descriptors": _serialize_descriptors(descriptors),
        "status": status,
    }


def match_features(
    descriptors1: list[list[int]] | np.ndarray,
    descriptors2: list[list[int]] | np.ndarray,
    ratio_threshold: float = _RATIO_TEST_THRESHOLD,
    score_threshold: float = _MATCH_SCORE_THRESHOLD,
) -> dict:
    """
    Match two sets of ORB descriptors using BFMatcher and Lowe's ratio test.

    Algorithm:
      1. Convert serialized lists back to (N, 32) uint8 arrays if needed.
      2. Run kNN match (k=2) with NORM_HAMMING distance (correct for ORB).
      3. Keep only pairs where  best_distance < ratio_threshold × second_best.
         This filters ambiguous / noisy matches.
      4. Score = (good_matches / min(N1, N2)) × 100, clamped to [0, 100].
      5. Verdict = "MATCH" when score ≥ score_threshold, else "NO MATCH".

    Args:
        descriptors1:    Descriptor set from image 1.  Accepts either the
                         nested-list format returned by ``extract_features``
                         or a raw (N, 32) uint8 ndarray.
        descriptors2:    Descriptor set from image 2.  Same formats accepted.
        ratio_threshold: Lowe ratio-test cutoff.  Default 0.75.
        score_threshold: Minimum score for a positive verdict.  Default 20.0.

    Returns::

        {
            "score":        42.5,       # float, 0–100
            "good_matches": 85,         # int, count of ratio-test survivors
            "total_matches": 200,       # int, raw kNN matches before filtering
            "verdict":      "MATCH"     # "MATCH" | "NO MATCH"
        }

    When either image has no descriptors the function returns score 0.0 and
    verdict "NO MATCH" rather than raising an exception, so callers can handle
    poor-quality images gracefully.
    """
    # ── Convert to numpy arrays ───────────────────────────────────────────────
    d1 = (
        np.array(descriptors1, dtype=np.uint8)
        if not isinstance(descriptors1, np.ndarray)
        else descriptors1
    )
    d2 = (
        np.array(descriptors2, dtype=np.uint8)
        if not isinstance(descriptors2, np.ndarray)
        else descriptors2
    )

    # ── Guard: empty descriptors ──────────────────────────────────────────────
    if d1.ndim != 2 or d2.ndim != 2 or d1.shape[0] == 0 or d2.shape[0] == 0:
        return {
            "score": 0.0,
            "good_matches": 0,
            "total_matches": 0,
            "verdict": "NO MATCH",
        }

    # ── BFMatcher with Hamming distance (required for ORB binary descriptors) ─
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)

    # knnMatch needs at least 2 training descriptors for k=2
    k = 2 if d2.shape[0] >= 2 else 1
    raw_matches = bf.knnMatch(d1, d2, k=k)

    # ── Lowe ratio test ───────────────────────────────────────────────────────
    good: list = []
    for pair in raw_matches:
        if len(pair) == 2:
            m, n = pair
            if m.distance < ratio_threshold * n.distance:
                good.append(m)
        elif len(pair) == 1:
            # Only one neighbour available (small descriptor set) — keep it
            good.append(pair[0])

    # ── Score normalised to 0–100 ─────────────────────────────────────────────
    max_possible = min(d1.shape[0], d2.shape[0])
    raw_score    = (len(good) / max_possible) * 100 if max_possible > 0 else 0.0
    score        = round(min(raw_score, 100.0), 2)

    return {
        "score":         score,
        "good_matches":  len(good),
        "total_matches": len(raw_matches),
        "verdict":       "MATCH" if score >= score_threshold else "NO MATCH",
    }
