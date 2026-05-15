"""
Minutiae-based fingerprint template extraction and matching.

This implements the two standard biometric primitives for fingerprints:

  Extraction — crossing-number method on the thinned skeleton:
    CN = 1  →  ridge ending
    CN = 3  →  bifurcation

  Matching — centroid-normalised spatial matching with rotation search:
    1. Translate both minutiae sets to their centroids.
    2. Rotate probe through 12 steps (0°–330° in 30° increments).
    3. For each rotation, count pairs within distance/angle tolerance.
    4. Score = 2×best_matches / (|probe| + |candidate|) × 100.

Score scale
-----------
  0–100 float.  Typical genuine match: 25–60+.
  Recommended starting threshold: 20.
  Calibrate using FAR/FRR measurements on your actual hardware.

This approach is correct for fingerprint biometrics (unlike ORB which is
a general-purpose computer vision descriptor). It is not as accurate as
SourceAFIS (which also performs global ridge-flow alignment), but it
requires no external dependencies beyond OpenCV and NumPy.
"""

from __future__ import annotations

import json
import math

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Configuration — tune these for your capture setup
# ---------------------------------------------------------------------------

_LOW_MINUTIAE_THRESHOLD: int = 10    # fewer than this → "low_quality"
_MAX_MINUTIAE: int          = 150   # cap noisy camera skeletons; prefer border-distant points
_DISTANCE_THRESHOLD: float  = 20.0  # pixels — spatial matching tolerance
_ANGLE_THRESHOLD: float     = math.pi / 6  # 30° — angle matching tolerance
_ROTATION_STEPS: int        = 12    # 30° increments covering 360°


# ---------------------------------------------------------------------------
# Extraction — crossing number method
# ---------------------------------------------------------------------------

def _crossing_number(patch: np.ndarray) -> int:
    """
    Crossing number of the center pixel in a 3×3 binary (0/1) neighborhood.
    Neighbors are read clockwise: NW, N, NE, E, SE, S, SW, W.
    CN=1 → ridge ending; CN=3 → bifurcation.
    """
    n = [
        patch[0, 0], patch[0, 1], patch[0, 2],
        patch[1, 2],
        patch[2, 2], patch[2, 1], patch[2, 0],
        patch[1, 0],
    ]
    return sum(1 for i in range(8) if n[i] == 0 and n[(i + 1) % 8] == 1)


def _ridge_angle(binary: np.ndarray, x: int, y: int, radius: int = 7) -> float:
    """
    Estimate the local ridge orientation angle at (x, y) using Sobel gradients
    on a local patch.  Returns angle in radians in [−π, π].
    """
    y1 = max(0, y - radius)
    y2 = min(binary.shape[0] - 1, y + radius)
    x1 = max(0, x - radius)
    x2 = min(binary.shape[1] - 1, x + radius)

    patch = binary[y1:y2 + 1, x1:x2 + 1].astype(np.float32)
    gx = cv2.Sobel(patch, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(patch, cv2.CV_32F, 0, 1, ksize=3)
    return float(np.arctan2(float(gy.mean()), float(gx.mean())))


def extract_minutiae(skeleton: np.ndarray) -> list[dict]:
    """
    Extract ridge endings and bifurcations from a thinned skeleton image.

    Args:
        skeleton: 2-D uint8 image (ridges = 255, background = 0).

    Returns:
        List of minutia dicts: {"x": int, "y": int, "type": str, "angle": float}
    """
    if skeleton.ndim != 2:
        skeleton = cv2.cvtColor(skeleton, cv2.COLOR_BGR2GRAY)

    binary = (skeleton > 0).astype(np.uint8)
    height, width = binary.shape
    minutiae: list[dict] = []

    # Skip a 2-pixel border to avoid edge artefacts
    for y in range(2, height - 2):
        for x in range(2, width - 2):
            if binary[y, x] == 0:
                continue

            cn = _crossing_number(binary[y - 1:y + 2, x - 1:x + 2])

            if cn == 1:
                m_type = "ending"
            elif cn == 3:
                m_type = "bifurcation"
            else:
                continue

            minutiae.append({
                "x":     int(x),
                "y":     int(y),
                "type":  m_type,
                "angle": _ridge_angle(binary, x, y),
            })

    # Cap to _MAX_MINUTIAE, preferring points furthest from image borders.
    # Border minutiae are more likely to be edge artefacts from camera captures.
    if len(minutiae) > _MAX_MINUTIAE:
        minutiae.sort(
            key=lambda m: min(m["x"], m["y"], width - m["x"], height - m["y"]),
            reverse=True,
        )
        minutiae = minutiae[:_MAX_MINUTIAE]

    return minutiae


# ---------------------------------------------------------------------------
# Serialization — JSON-safe for storage in the encrypted DB column
# ---------------------------------------------------------------------------

def template_to_dict(minutiae: list[dict]) -> dict:
    """Wrap minutiae in a versioned, JSON-serialisable template dict."""
    return {
        "format":         "minutiae_v1",
        "minutiae_count": len(minutiae),
        "minutiae":       minutiae,
        "status": (
            "no_features" if len(minutiae) == 0
            else "low_quality" if len(minutiae) < _LOW_MINUTIAE_THRESHOLD
            else "ok"
        ),
    }


def template_from_dict(template_dict: dict) -> list[dict]:
    """Deserialize the minutiae list from a stored template dict."""
    return template_dict.get("minutiae", [])


# ---------------------------------------------------------------------------
# Matching — centroid-normalised spatial matching with rotation search
# ---------------------------------------------------------------------------

def _angle_diff(a: float, b: float) -> float:
    """Smallest unsigned difference between two angles (radians)."""
    d = abs(a - b) % (2 * math.pi)
    return d if d <= math.pi else (2 * math.pi - d)


def _count_matches(
    probe: list[dict],
    candidate: list[dict],
    rotation: float,
) -> int:
    """
    Count matching minutia pairs after rotating probe by `rotation` radians.
    Each candidate minutia is matched at most once (greedy, closest first).
    """
    cos_r, sin_r = math.cos(rotation), math.sin(rotation)

    # Rotate probe around its own centroid (already zeroed)
    rotated = [
        {
            "x":     m["x"] * cos_r - m["y"] * sin_r,
            "y":     m["x"] * sin_r + m["y"] * cos_r,
            "angle": m["angle"] + rotation,
            "type":  m["type"],
        }
        for m in probe
    ]

    used: set[int] = set()
    matches = 0

    for p in rotated:
        best_dist  = _DISTANCE_THRESHOLD + 1.0
        best_idx   = -1

        for i, c in enumerate(candidate):
            if i in used:
                continue
            if p["type"] != c["type"]:
                continue

            dist = math.hypot(p["x"] - c["x"], p["y"] - c["y"])
            if dist >= _DISTANCE_THRESHOLD:
                continue
            if _angle_diff(p["angle"], c["angle"]) >= _ANGLE_THRESHOLD:
                continue

            if dist < best_dist:
                best_dist = dist
                best_idx  = i

        if best_idx >= 0:
            matches += 1
            used.add(best_idx)

    return matches


def _normalize_to_centroid(minutiae: list[dict]) -> list[dict]:
    """Translate minutiae set so its centroid is at the origin."""
    if not minutiae:
        return minutiae
    cx = sum(m["x"] for m in minutiae) / len(minutiae)
    cy = sum(m["y"] for m in minutiae) / len(minutiae)
    return [
        {**m, "x": m["x"] - cx, "y": m["y"] - cy}
        for m in minutiae
    ]


def match_minutiae(probe: list[dict], candidate: list[dict]) -> float:
    """
    Match two minutiae lists and return a score in [0, 100].

    Uses centroid normalisation + rotation search to handle placement variation.
    Score = 2 × best_matches / (|probe| + |candidate|) × 100.

    Args:
        probe:     Minutiae from the finger being verified.
        candidate: Minutiae from the enrolled template.

    Returns:
        Float score 0–100.  Compare against MATCH_THRESHOLD (default 20).
    """
    if not probe or not candidate:
        return 0.0

    probe_n = _normalize_to_centroid(probe)
    cand_n  = _normalize_to_centroid(candidate)

    total   = len(probe) + len(candidate)
    best    = 0

    for step in range(_ROTATION_STEPS):
        rotation = (2 * math.pi * step) / _ROTATION_STEPS
        matches  = _count_matches(probe_n, cand_n, rotation)
        if matches > best:
            best = matches

    return round(min((2 * best / total) * 100, 100.0), 2)
