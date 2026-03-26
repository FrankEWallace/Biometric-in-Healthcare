"""
Image preprocessing pipeline for fingerprint images.

Pipeline:
  raw image
    → grayscale
    → Gaussian blur        (noise reduction)
    → histogram equalization  (contrast enhancement)
    → adaptive thresholding   (binarization)
    → morphological thinning  (skeleton / ridge thinning)

All functions are pure and stateless — safe to call from any request.

Note on thinning:
  opencv-contrib's cv2.ximgproc.thinning is NOT required.
  Thinning is implemented via an iterative morphological skeleton
  (erosion + open), which works with base opencv-python.
"""

from __future__ import annotations

import base64

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Step 1 — Grayscale
# ---------------------------------------------------------------------------

def to_grayscale(image: np.ndarray) -> np.ndarray:
    """Convert a BGR or already-grayscale image to single-channel gray."""
    if len(image.shape) == 3 and image.shape[2] == 3:
        return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return image.copy()


# ---------------------------------------------------------------------------
# Step 2 — Gaussian blur
# ---------------------------------------------------------------------------

def apply_gaussian_blur(image: np.ndarray, ksize: int = 5) -> np.ndarray:
    """
    Smooth the image with a Gaussian kernel to reduce sensor noise.

    Args:
        image: Grayscale uint8 image.
        ksize: Kernel size (must be odd). Default 5×5.
    """
    if ksize % 2 == 0:
        ksize += 1
    return cv2.GaussianBlur(image, (ksize, ksize), sigmaX=0)


# ---------------------------------------------------------------------------
# Step 3 — Histogram equalization
# ---------------------------------------------------------------------------

def equalize_histogram(image: np.ndarray) -> np.ndarray:
    """
    Apply standard histogram equalization to enhance ridge/valley contrast.

    Spreads intensity values across the full [0, 255] range so that
    subsequent thresholding works more reliably across varied lighting.
    """
    return cv2.equalizeHist(image)


# ---------------------------------------------------------------------------
# Step 4 — Adaptive thresholding (binarization)
# ---------------------------------------------------------------------------

def apply_adaptive_threshold(
    image: np.ndarray,
    block_size: int = 11,
    c: int = 2,
) -> np.ndarray:
    """
    Binarize the image using Gaussian adaptive thresholding.

    Unlike global thresholding, adaptive thresholding computes a local
    threshold for each pixel neighbourhood, making it robust to uneven
    illumination across the fingerprint image.

    Args:
        image:      Grayscale uint8 image (output of histogram equalization).
        block_size: Size of the pixel neighbourhood used to compute the
                    threshold (must be odd, ≥ 3). Default 11.
        c:          Constant subtracted from the weighted mean. Positive
                    values raise the threshold, reducing noise pixels in
                    the foreground. Default 2.

    Returns:
        Binary image: ridge pixels = 255 (white), background = 0 (black).

    Note:
        THRESH_BINARY_INV is used because camera-captured fingerprints
        typically show ridges as darker regions against a lighter background.
        Inversion makes ridges the white foreground, which is the expected
        input for skeletonization.
    """
    if block_size % 2 == 0:
        block_size += 1
    return cv2.adaptiveThreshold(
        image,
        maxValue=255,
        adaptiveMethod=cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        thresholdType=cv2.THRESH_BINARY_INV,
        blockSize=block_size,
        C=c,
    )


# ---------------------------------------------------------------------------
# Step 5 — Morphological thinning (skeletonization)
# ---------------------------------------------------------------------------

def apply_thinning(binary_image: np.ndarray) -> np.ndarray:
    """
    Reduce binary ridge regions to single-pixel-wide lines (skeleton).

    Algorithm — iterative morphological skeleton:
      At each iteration:
        1. Erode the image with a 3×3 cross kernel.
        2. Dilate the eroded result (morphological open).
        3. Subtract the opened result from the pre-erosion image to
           capture the pixels removed by this erosion step.
        4. OR those pixels into the growing skeleton.
        5. Replace the working image with the eroded result.
      Stop when nothing remains after erosion (all foreground consumed).

    This produces a connected 1-pixel-wide ridge skeleton without
    requiring opencv-contrib or external libraries.

    Args:
        binary_image: Binary uint8 image (ridges = 255).

    Returns:
        Skeleton image (same dtype/size as input).
    """
    skeleton = np.zeros_like(binary_image)
    kernel = cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))
    working = binary_image.copy()

    while True:
        eroded = cv2.erode(working, kernel)
        opened = cv2.dilate(eroded, kernel)           # erode then dilate = open
        contribution = cv2.subtract(working, opened)  # pixels lost in this step
        skeleton = cv2.bitwise_or(skeleton, contribution)
        working = eroded.copy()

        if cv2.countNonZero(working) == 0:
            break

    return skeleton


# ---------------------------------------------------------------------------
# Quality score
# ---------------------------------------------------------------------------

def compute_quality_score(image: np.ndarray) -> float:
    """
    Estimate sharpness using Laplacian variance, normalised to [0.0, 1.0].

    Higher variance → sharper ridges → higher score.
    Values below 0.30 indicate a poor-quality capture.
    Ceiling of 2000 is an empirical upper bound for typical fingerprint images.
    """
    laplacian_var = float(cv2.Laplacian(image, cv2.CV_64F).var())
    return round(min(laplacian_var / 2000.0, 1.0), 3)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def preprocess_fingerprint(image: np.ndarray) -> dict:
    """
    Run the full preprocessing pipeline on a raw BGR or grayscale image.

    Steps applied in order:
      1. Grayscale conversion
      2. Gaussian blur              — noise reduction
      3. Histogram equalization     — contrast enhancement
      4. Adaptive thresholding      — binarization
      5. Morphological thinning     — ridge skeletonization

    The quality score is computed on the equalized (pre-binary) image so
    that the Laplacian variance reflects actual ridge sharpness rather than
    the high-frequency edges introduced by binarization.

    Returns::

        {
            "processed_image": "<base64-encoded PNG of skeleton>",
            "quality_score": 0.742,
            "steps": [
                "grayscale",
                "gaussian_blur",
                "histogram_equalization",
                "adaptive_threshold",
                "thinning"
            ]
        }
    """
    gray      = to_grayscale(image)
    blurred   = apply_gaussian_blur(gray)
    equalized = equalize_histogram(blurred)
    binary    = apply_adaptive_threshold(equalized)
    skeleton  = apply_thinning(binary)

    quality = compute_quality_score(equalized)

    _, buffer = cv2.imencode(".png", skeleton)
    b64 = base64.b64encode(buffer).decode("utf-8")

    return {
        "processed_image": b64,
        "quality_score": quality,
        "steps": [
            "grayscale",
            "gaussian_blur",
            "histogram_equalization",
            "adaptive_threshold",
            "thinning",
        ],
    }
