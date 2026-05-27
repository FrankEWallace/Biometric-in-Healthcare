"""
Fingerprint template extraction and matching — SourceAFIS-compatible interface.

SourceAFIS is a Java/.NET library (https://sourceafis.machinezoo.com/) with no
official Python PyPI package.  This module exposes the same extract/match
interface backed by our native OpenCV crossing-number minutiae algorithm.

Pipeline summary:
  image → orientation-guided Gabor enhancement (image_processor.py)
        → crossing-number minutiae extraction
        → centroid-normalised rotation-search matching

See minutiae_service.py for the full algorithm documentation.
"""

from __future__ import annotations

import numpy as np

from app.services.minutiae_service import (
    extract_minutiae,
    template_to_dict,
    template_from_dict,
    match_minutiae,
)


def extract_template(grayscale_image: np.ndarray, dpi: int = 500) -> dict:
    """
    Build a minutiae template from a preprocessed skeleton image.

    Args:
        grayscale_image: 2-D uint8 numpy array (skeleton from image_processor.py).
        dpi:             Reserved for future use (DPI annotation on template).

    Returns:
        JSON-serialisable dict stored encrypted via Laravel Crypt.
    """
    minutiae = extract_minutiae(grayscale_image)
    return template_to_dict(minutiae)


def match_templates(probe_dict: dict, candidate_dict: dict) -> float:
    """
    Match two minutiae templates and return a raw score in [0, 100].

    Args:
        probe_dict:     Dict returned by extract_template() for the probe.
        candidate_dict: Dict returned by extract_template() for the candidate.

    Returns:
        Score 0–100.  Recommended threshold: 20.
        Calibrate using FAR/FRR measurements on your hardware.
    """
    probe     = template_from_dict(probe_dict)
    candidate = template_from_dict(candidate_dict)
    return match_minutiae(probe, candidate)
