"""
Fingerprint endpoints consumed by the Laravel backend.

POST /process              — base64 image → SourceAFIS template + quality score
POST /match                — probe template + candidate list → best patient_id + score
POST /process-fingerprint  — multipart image → SourceAFIS template + quality score
POST /match-fingerprint    — two multipart images → verdict + score
"""

from __future__ import annotations

import base64
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel, field_validator

from app.services.image_processor import preprocess_fingerprint, to_grayscale
from app.services.sourceafis_service import extract_template, match_templates

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

def _decode_base64_image(b64: str) -> np.ndarray:
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


def _decode_upload(contents: bytes, field_name: str) -> np.ndarray:
    """Decode raw upload bytes into an OpenCV BGR array."""
    buf = np.frombuffer(contents, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(
            status_code=400,
            detail=f"'{field_name}' could not be decoded. Ensure it is a valid JPEG or PNG.",
        )
    return img


def _preprocess_to_skeleton(img: np.ndarray) -> tuple[np.ndarray, float, list[str]]:
    """
    Run the full preprocessing pipeline and return (skeleton_gray, quality_score, steps).
    The skeleton is a single-channel uint8 array suitable for SourceAFIS.
    """
    result         = preprocess_fingerprint(img)
    quality_score  = result["quality_score"]
    steps          = result["steps"]

    skeleton_bytes = base64.b64decode(result["processed_image"])
    skeleton_buf   = np.frombuffer(skeleton_bytes, dtype=np.uint8)
    skeleton_gray  = cv2.imdecode(skeleton_buf, cv2.IMREAD_GRAYSCALE)

    if skeleton_gray is None:
        raise HTTPException(status_code=500, detail="Preprocessing produced an unreadable skeleton.")

    return skeleton_gray, quality_score, steps


# ---------------------------------------------------------------------------
# POST /process  (base64 — used by VerificationController hospital-wide scan)
# ---------------------------------------------------------------------------

@router.post(
    "/process",
    response_model=ProcessResponse,
    summary="Extract SourceAFIS template from a base64 fingerprint image",
)
def process(body: ProcessRequest) -> ProcessResponse:
    """
    Accepts a base64-encoded fingerprint image, runs the full preprocessing
    pipeline (grayscale → blur → equalization → threshold → thinning), then
    extracts a SourceAFIS minutiae template.

    The returned template dict is opaque to callers — pass it unchanged to
    POST /match as a candidate or probe template.
    """
    img = _decode_base64_image(body.image)
    skeleton, quality_score, _ = _preprocess_to_skeleton(img)
    template = extract_template(skeleton)

    return ProcessResponse(template=template, quality_score=quality_score)


# ---------------------------------------------------------------------------
# POST /match  (SourceAFIS — used by both controllers)
# ---------------------------------------------------------------------------

@router.post(
    "/match",
    response_model=MatchResponse,
    summary="Match a probe template against a list of candidates",
)
def match(body: MatchRequest) -> MatchResponse:
    """
    Runs SourceAFIS minutiae matching between the probe and every candidate.
    Returns the patient_id with the highest score.

    Score scale: SourceAFIS raw float (typically 0–200+).
    Recommended threshold: 40.  Calibrate based on FAR/FRR measurements.
    """
    if not body.candidates:
        raise HTTPException(status_code=400, detail="'candidates' list is empty.")

    best_score: float = -1.0
    best_id: int | None = None

    for candidate in body.candidates:
        try:
            score = match_templates(body.probe, candidate.template)
        except Exception:
            score = 0.0

        if score > best_score:
            best_score = score
            best_id    = candidate.patient_id

    if best_id is None:
        raise HTTPException(status_code=400, detail="No valid candidates could be processed.")

    return MatchResponse(patient_id=best_id, score=round(best_score, 4))


# ---------------------------------------------------------------------------
# POST /process-fingerprint  (multipart — used by FingerprintController)
# ---------------------------------------------------------------------------

_ALLOWED_TYPES = ("image/jpeg", "image/png", "image/jpg")


@router.post(
    "/process-fingerprint",
    summary="Preprocess a fingerprint image and extract a SourceAFIS template",
)
async def process_fingerprint(file: UploadFile = File(...)) -> dict:
    """
    Full pipeline for an uploaded fingerprint image (JPEG or PNG):

      1. Preprocessing  — grayscale → Gaussian blur → histogram equalization
                          → adaptive threshold → morphological thinning
      2. Template extraction — SourceAFIS minutiae detection

    Feature ``status`` field:
      - ``"ok"``          — sufficient minutiae for reliable matching
      - ``"low_quality"`` — fewer than 10 minutiae; match result unreliable
      - ``"no_features"`` — blank or unreadable image; reject the capture
    """
    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{file.content_type}'. Use JPEG or PNG.",
        )

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    img = _decode_upload(contents, "file")
    skeleton, quality_score, steps = _preprocess_to_skeleton(img)
    template = extract_template(skeleton)

    _, buffer = cv2.imencode(".png", skeleton)
    processed_image_b64 = base64.b64encode(buffer).decode("utf-8")

    return {
        "success":         True,
        "message":         "Image processed successfully.",
        "filename":        file.filename,
        "quality_score":   quality_score,
        "steps_applied":   steps,
        "processed_image": processed_image_b64,
        "features": {
            "minutiae_count": template["minutiae_count"],
            "status":         template["status"],
            "format":         template["format"],
            "data":           template["data"],
            # probe_keypoints alias kept for Laravel FingerprintService compatibility
            "keypoint_count": template["minutiae_count"],
        },
    }


# ---------------------------------------------------------------------------
# POST /match-fingerprint  (two images — direct image-to-image comparison)
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
      2. Preprocess each image (full pipeline through thinning).
      3. Extract SourceAFIS minutiae template from each skeleton.
      4. Match templates with SourceAFIS and return score + verdict.

    Verdict threshold: score ≥ 40 → MATCH.
    """
    _MATCH_THRESHOLD = 40.0

    for field_name, upload in [("image1", image1), ("image2", image2)]:
        if upload.content_type not in _ALLOWED_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"'{field_name}' has unsupported type '{upload.content_type}'.",
            )

    bytes1 = await image1.read()
    bytes2 = await image2.read()

    if not bytes1:
        raise HTTPException(status_code=400, detail="'image1' file is empty.")
    if not bytes2:
        raise HTTPException(status_code=400, detail="'image2' file is empty.")

    img1 = _decode_upload(bytes1, "image1")
    img2 = _decode_upload(bytes2, "image2")

    skeleton1, _, _ = _preprocess_to_skeleton(img1)
    skeleton2, _, _ = _preprocess_to_skeleton(img2)

    t1 = extract_template(skeleton1)
    t2 = extract_template(skeleton2)

    score = match_templates(t1, t2)

    return {
        "verdict":       "MATCH" if score >= _MATCH_THRESHOLD else "NO MATCH",
        "score":         round(score, 2),
        "image1": {
            "filename":       image1.filename,
            "minutiae_count": t1["minutiae_count"],
            "feature_status": t1["status"],
        },
        "image2": {
            "filename":       image2.filename,
            "minutiae_count": t2["minutiae_count"],
            "feature_status": t2["status"],
        },
    }
