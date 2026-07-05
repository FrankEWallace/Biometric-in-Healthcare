"""
Four-finger ("hand slap") endpoints consumed by the Laravel backend.

POST /process-hand   — hand photo → segment into 4 finger crops → 4 templates
POST /match-hand     — probe hand (4 templates) vs candidate hands → fused best

These are the four-finger counterparts of /process and /match. They are
matcher-agnostic: extraction and scoring go through the domain-routed
``Matcher`` (minutiae today, learned embedding once installed), and per-finger
scores are fused (mean by default). A phone photo of a hand already contains
four fingers, so this matches the intended capture UX and the NISTIR-8307
finding that a four-finger slap is far more accurate than a single finger.

Templates are opaque dicts, keyed by ``finger_position`` — Laravel stores one
encrypted ``fingerprints`` row per finger and passes them back unchanged.
"""

from __future__ import annotations

import base64
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator

from app.services.hand_segmentation import SegmentationError, segment_hand
from app.services.matcher import get_matcher, match_hands

router = APIRouter(tags=["hand"])

# Only fuse when at least this many finger positions overlap; below it the
# hands aren't comparable and we return no-match rather than risk a false accept.
_MIN_FINGERS = 3


def _decode_b64(b64: str, field: str) -> np.ndarray:
    try:
        raw = base64.b64decode(b64)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"'{field}': invalid base64 ({exc})")
    img = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail=f"'{field}': not a decodable JPEG/PNG")
    return img


# ---------------------------------------------------------------------------
# POST /process-hand
# ---------------------------------------------------------------------------

class ProcessHandRequest(BaseModel):
    image: str                      # base64 whole-hand photo
    hand: str = "right"             # "right" | "left" — orientation for finger naming
    domain: str = "contactless"     # capture domain → matcher routing

    @field_validator("image")
    @classmethod
    def _nonempty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("'image' must not be empty.")
        return v

    @field_validator("hand")
    @classmethod
    def _hand(cls, v: str) -> str:
        if v.lower() not in ("right", "left"):
            raise ValueError("'hand' must be 'right' or 'left'.")
        return v.lower()


class FingerTemplate(BaseModel):
    finger_position: str
    template: dict[str, Any]
    quality_score: float
    bbox: list[int]


class ProcessHandResponse(BaseModel):
    matcher: str
    domain: str
    fingers: list[FingerTemplate]


@router.post(
    "/process-hand",
    response_model=ProcessHandResponse,
    summary="Segment a hand photo into 4 fingers and extract a template per finger",
)
def process_hand(body: ProcessHandRequest) -> ProcessHandResponse:
    """
    Segment a whole-hand photo into up to four per-finger crops and extract a
    template from each, keyed by ``finger_position``. Enrollment stores one
    ``fingerprints`` row per returned finger; verification sends the templates
    to /match-hand.

    The matcher is chosen by ``domain`` (contactless → embedding when installed,
    else the minutiae fallback). ``matcher`` in the response names what actually
    ran, so callers can tell when they're on the placeholder.
    """
    img = _decode_b64(body.image, "image")
    matcher = get_matcher(body.domain)

    try:
        crops = segment_hand(img, hand=body.hand, want=4)
    except SegmentationError as exc:
        raise HTTPException(status_code=422, detail=f"Hand segmentation failed: {exc}")

    # Contactless captures need enhancement; contact sensors don't.
    enhance = body.domain != "contact"
    fingers: list[FingerTemplate] = []
    for crop in crops:
        template = matcher.extract(crop.image, enhance=enhance, hand=body.hand)
        fingers.append(
            FingerTemplate(
                finger_position=crop.finger_position or f"finger_{crop.order}",
                template=template,
                quality_score=float(template.get("quality_score", 0.0)),
                bbox=list(crop.bbox),
            )
        )

    return ProcessHandResponse(matcher=matcher.name, domain=body.domain, fingers=fingers)


# ---------------------------------------------------------------------------
# POST /match-hand
# ---------------------------------------------------------------------------

class CandidateHand(BaseModel):
    patient_id: int
    fingers: dict[str, dict[str, Any]]   # finger_position -> template


class MatchHandRequest(BaseModel):
    probe: dict[str, dict[str, Any]]     # finger_position -> template
    candidates: list[CandidateHand]
    domain: str = "contactless"
    fusion: str = "mean"                 # mean | max | min
    min_fingers: int = _MIN_FINGERS


class MatchHandResponse(BaseModel):
    patient_id: int
    score: float
    matcher: str
    fingers_used: list[str]
    per_finger: dict[str, float]


@router.post(
    "/match-hand",
    response_model=MatchHandResponse,
    summary="Match a probe hand against candidate hands with per-finger fusion",
)
def match_hand(body: MatchHandRequest) -> MatchHandResponse:
    """
    Match a four-finger probe against each candidate hand, fusing the shared
    fingers' scores. Returns the best patient with the fused score plus the
    per-finger breakdown (for audit/explainability). Laravel compares the fused
    score against the domain-appropriate threshold.
    """
    if not body.candidates:
        raise HTTPException(status_code=400, detail="'candidates' list is empty.")

    matcher = get_matcher(body.domain)

    best_score = -1.0
    best_id: int | None = None
    best_used: list[str] = []
    best_per: dict[str, float] = {}

    for cand in body.candidates:
        try:
            fused, used, per = match_hands(
                body.probe,
                cand.fingers,
                matcher=matcher,
                min_fingers=body.min_fingers,
                fusion=body.fusion,
            )
        except Exception:  # noqa: BLE001 - a bad candidate must not kill the scan
            fused, used, per = 0.0, [], {}

        if fused > best_score:
            best_score, best_id, best_used, best_per = fused, cand.patient_id, used, per

    if best_id is None:
        raise HTTPException(status_code=400, detail="No candidate hand could be scored.")

    return MatchHandResponse(
        patient_id=best_id,
        score=round(best_score, 4),
        matcher=matcher.name,
        fingers_used=best_used,
        per_finger={k: round(v, 4) for k, v in best_per.items()},
    )
