"""
Fingerprint endpoints consumed by the Laravel backend.

POST /process  — base64 image → ORB template + quality score
POST /match    — probe template + candidate list → best patient_id + score
"""

from __future__ import annotations

import base64
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel, field_validator

from app.services.processor import build_template, match_templates
from app.services.image_processor import preprocess_fingerprint
from app.services.feature_extractor import extract_features, match_features

router = APIRouter(tags=["fingerprint"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------

class ProcessRequest(BaseModel):
    image: str  # base64-encoded JPEG or PNG

    @field_validator("image")
    @classmethod
    def must_be_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("'image' must not be empty.")
        return v


class ProcessResponse(BaseModel):
    template: dict[str, Any]
    quality_score: float


class Candidate(BaseModel):
    patient_id: int
    template: dict[str, Any]


class MatchRequest(BaseModel):
    probe: dict[str, Any]
    candidates: list[Candidate]


class MatchResponse(BaseModel):
    patient_id: int
    score: float


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _decode_image(b64: str) -> np.ndarray:
    """Decode a base64 string into an OpenCV BGR image array."""
    try:
        image_bytes = base64.b64decode(b64)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid base64 data: {exc}")

    buf = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(
            status_code=400,
            detail="Could not decode image. Ensure it is a valid JPEG or PNG.",
        )
    return img


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post(
    "/process",
    response_model=ProcessResponse,
    summary="Extract ORB template from a fingerprint image",
)
def process(body: ProcessRequest) -> ProcessResponse:
    """
    Accepts a base64-encoded fingerprint image, runs the full processing
    pipeline (CLAHE → Gabor → ORB), and returns the feature template along
    with a quality score in [0, 1].

    A quality score below **0.30** indicates a poor capture and should be
    rejected by the caller.
    """
    image = _decode_image(body.image)
    result = build_template(image)
    return ProcessResponse(
        template=result["template"],
        quality_score=result["quality_score"],
    )


@router.post(
    "/match",
    response_model=MatchResponse,
    summary="Match a probe template against a list of candidates",
)
def match(body: MatchRequest) -> MatchResponse:
    """
    Runs a ratio-test BFMatcher comparison between the probe template and
    every candidate. Returns the patient_id with the highest score.
    """
    if not body.candidates:
        raise HTTPException(status_code=400, detail="'candidates' list is empty.")

    best_score = -1.0
    best_id: int | None = None

    for candidate in body.candidates:
        score = match_templates(body.probe, candidate.template)
        if score > best_score:
            best_score = score
            best_id = candidate.patient_id

    if best_id is None:
        raise HTTPException(
            status_code=400, detail="No valid candidates could be processed."
        )

    return MatchResponse(patient_id=best_id, score=round(best_score, 4))


@router.post(
    "/process-fingerprint",
    summary="Preprocess a fingerprint image and extract ORB features",
)
async def process_fingerprint(file: UploadFile = File(...)) -> dict:
    """
    Full pipeline for an uploaded fingerprint image (JPEG or PNG):

      1. Preprocessing  — grayscale → Gaussian blur → histogram equalization
                          → adaptive threshold → morphological thinning
      2. Feature extraction — ORB keypoint detection + BRIEF descriptor computation

    Returns the skeleton image (base64 PNG), quality score, and the ORB
    feature set ready for matching.

    Feature ``status`` field:
      - ``"ok"``          — sufficient features for reliable matching
      - ``"low_quality"`` — fewer than 10 keypoints; match result unreliable
      - ``"no_features"`` — blank or unreadable image; reject the capture
    """
    if file.content_type not in ("image/jpeg", "image/png", "image/jpg"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{file.content_type}'. Use JPEG or PNG.",
        )

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    buf = np.frombuffer(contents, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(
            status_code=400,
            detail="Could not decode image. Ensure it is a valid JPEG or PNG.",
        )

    preprocessed = preprocess_fingerprint(img)

    # Decode skeleton back to ndarray so feature extractor operates on
    # the fully processed (thinned) image rather than the raw upload.
    skeleton_bytes = base64.b64decode(preprocessed["processed_image"])
    skeleton_buf   = np.frombuffer(skeleton_bytes, dtype=np.uint8)
    skeleton_img   = cv2.imdecode(skeleton_buf, cv2.IMREAD_GRAYSCALE)

    features = extract_features(skeleton_img)

    return {
        "success": True,
        "message": "Image processed successfully.",
        "filename": file.filename,
        "quality_score": preprocessed["quality_score"],
        "steps_applied": preprocessed["steps"],
        "processed_image": preprocessed["processed_image"],
        "features": {
            "keypoint_count": features["keypoint_count"],
            "status": features["status"],
            "keypoints": features["keypoints"],
            "descriptors": features["descriptors"],
        },
    }


# ---------------------------------------------------------------------------
# Helpers shared by match-fingerprint
# ---------------------------------------------------------------------------

def _load_image_from_upload(upload_bytes: bytes, field_name: str) -> np.ndarray:
    """Decode raw upload bytes → OpenCV BGR array, or raise HTTP 400."""
    buf = np.frombuffer(upload_bytes, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(
            status_code=400,
            detail=f"'{field_name}' could not be decoded. Ensure it is a valid JPEG or PNG.",
        )
    return img


def _preprocess_to_gray(img: np.ndarray) -> np.ndarray:
    """Run full preprocessing pipeline and return the skeleton as a grayscale ndarray."""
    prep           = preprocess_fingerprint(img)
    skeleton_bytes = base64.b64decode(prep["processed_image"])
    skeleton_buf   = np.frombuffer(skeleton_bytes, dtype=np.uint8)
    return cv2.imdecode(skeleton_buf, cv2.IMREAD_GRAYSCALE)


# ---------------------------------------------------------------------------
# POST /match-fingerprint
# ---------------------------------------------------------------------------

@router.post(
    "/match-fingerprint",
    summary="Compare two fingerprint images and return a MATCH / NO MATCH verdict",
)
async def match_fingerprint(
    image1: UploadFile = File(..., description="First fingerprint image (JPEG or PNG)"),
    image2: UploadFile = File(..., description="Second fingerprint image (JPEG or PNG)"),
) -> dict:
    """
    Full matching pipeline for two uploaded fingerprint images:

      1. Validate and decode both files.
      2. Preprocess each image (grayscale → blur → equalization →
         adaptive threshold → thinning).
      3. Extract ORB keypoints + BRIEF descriptors from each skeleton.
      4. Match descriptors with BFMatcher (NORM_HAMMING) + Lowe ratio test.
      5. Compute a normalised score in [0, 100] and return a verdict.

    Verdict thresholds:
      - Score ≥ 20 → **MATCH**
      - Score < 20 → **NO MATCH**

    Both images must be JPEG or PNG.  If either image is blank or yields no
    features the endpoint returns score 0.0 and verdict "NO MATCH" without
    raising an error.
    """
    _ALLOWED = ("image/jpeg", "image/png", "image/jpg")

    if image1.content_type not in _ALLOWED:
        raise HTTPException(
            status_code=400,
            detail=f"'image1' has unsupported type '{image1.content_type}'. Use JPEG or PNG.",
        )
    if image2.content_type not in _ALLOWED:
        raise HTTPException(
            status_code=400,
            detail=f"'image2' has unsupported type '{image2.content_type}'. Use JPEG or PNG.",
        )

    bytes1 = await image1.read()
    bytes2 = await image2.read()

    if not bytes1:
        raise HTTPException(status_code=400, detail="'image1' file is empty.")
    if not bytes2:
        raise HTTPException(status_code=400, detail="'image2' file is empty.")

    # ── Decode ────────────────────────────────────────────────────────────────
    img1 = _load_image_from_upload(bytes1, "image1")
    img2 = _load_image_from_upload(bytes2, "image2")

    # ── Preprocess ────────────────────────────────────────────────────────────
    skeleton1 = _preprocess_to_gray(img1)
    skeleton2 = _preprocess_to_gray(img2)

    # ── Extract features ──────────────────────────────────────────────────────
    features1 = extract_features(skeleton1)
    features2 = extract_features(skeleton2)

    # ── Match ─────────────────────────────────────────────────────────────────
    result = match_features(features1["descriptors"], features2["descriptors"])

    return {
        "verdict":       result["verdict"],
        "score":         result["score"],
        "good_matches":  result["good_matches"],
        "total_matches": result["total_matches"],
        "image1": {
            "filename":       image1.filename,
            "keypoint_count": features1["keypoint_count"],
            "feature_status": features1["status"],
        },
        "image2": {
            "filename":       image2.filename,
            "keypoint_count": features2["keypoint_count"],
            "feature_status": features2["status"],
        },
    }
