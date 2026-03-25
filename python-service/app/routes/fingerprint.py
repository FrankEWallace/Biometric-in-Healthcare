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
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator

from app.services.processor import build_template, match_templates

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
