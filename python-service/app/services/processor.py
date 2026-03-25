"""
Fingerprint processing logic.

Pipeline:
  raw image → CLAHE enhancement → Gabor filter bank → ORB keypoints/descriptors

All functions are pure and stateless — safe to call from any request.
"""

from __future__ import annotations

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Preprocessing
# ---------------------------------------------------------------------------

def preprocess(image: np.ndarray) -> np.ndarray:
    """Convert to grayscale and apply CLAHE for contrast normalisation."""
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def apply_gabor(image: np.ndarray) -> np.ndarray:
    """Apply a bank of Gabor filters at four orientations and return the max response."""
    responses = []
    for theta in np.arange(0, np.pi, np.pi / 4):
        kernel = cv2.getGaborKernel(
            ksize=(21, 21),
            sigma=5.0,
            theta=float(theta),
            lambd=10.0,
            gamma=0.5,
            psi=0,
            ktype=cv2.CV_32F,
        )
        responses.append(cv2.filter2D(image, cv2.CV_8UC3, kernel))
    return np.max(np.stack(responses, axis=0), axis=0)


# ---------------------------------------------------------------------------
# Feature extraction
# ---------------------------------------------------------------------------

def extract_orb_template(image: np.ndarray) -> dict:
    """Detect ORB keypoints/descriptors. Returns a JSON-serialisable dict."""
    orb = cv2.ORB_create(nfeatures=500)
    keypoints, descriptors = orb.detectAndCompute(image, None)

    if descriptors is None:
        descriptors = np.zeros((0, 32), dtype=np.uint8)

    kp_data = [
        {
            "pt": list(kp.pt),
            "size": kp.size,
            "angle": kp.angle,
            "response": kp.response,
            "octave": kp.octave,
            "class_id": kp.class_id,
        }
        for kp in keypoints
    ]

    return {"keypoints": kp_data, "descriptors": descriptors.tolist()}


def compute_quality_score(keypoints: list, _image: np.ndarray) -> float:
    """Quality score [0, 1] — ratio of detected keypoints to the 500-feature target."""
    if not keypoints:
        return 0.0
    return min(len(keypoints) / 500.0, 1.0)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def build_template(image: np.ndarray) -> dict:
    """
    Full pipeline: CLAHE → Gabor → ORB.

    Returns::

        {
            "template": {"keypoints": [...], "descriptors": [[...]]},
            "quality_score": 0.742
        }
    """
    enhanced = preprocess(image)
    gabor_out = apply_gabor(enhanced)
    orb_result = extract_orb_template(gabor_out)
    quality = compute_quality_score(orb_result["keypoints"], gabor_out)
    return {"template": orb_result, "quality_score": round(quality, 3)}


def match_templates(probe: dict, candidate: dict) -> float:
    """
    Ratio-test BFMatcher score [0, 1] between two ORB templates.
    Returns 0.0 if either template has no descriptors.
    """
    probe_desc = np.array(probe["descriptors"], dtype=np.uint8)
    cand_desc = np.array(candidate["descriptors"], dtype=np.uint8)

    if probe_desc.shape[0] == 0 or cand_desc.shape[0] == 0:
        return 0.0

    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)
    matches = bf.knnMatch(probe_desc, cand_desc, k=2)

    good = [
        m for m_pair in matches
        if len(m_pair) == 2
        for m, n in [m_pair]
        if m.distance < 0.75 * n.distance
    ]

    max_possible = min(probe_desc.shape[0], cand_desc.shape[0])
    return len(good) / max_possible if max_possible > 0 else 0.0
