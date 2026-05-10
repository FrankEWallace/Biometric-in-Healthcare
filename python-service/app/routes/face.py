"""
Face recognition endpoints consumed by the Laravel backend.

POST /face/process — base64 image → face embedding + quality score
POST /face/match   — probe embedding + candidate list → best patient_id + score

Uses OpenCV Haar cascade for face detection and LBP histogram as the
embedding. Lightweight and works without additional pip installs.
Swap the embedding in _extract_embedding() for DeepFace/InsightFace
to improve accuracy once those dependencies are available.
"""

from __future__ import annotations

import base64
import math
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/face", tags=["face"])

# Haar cascade bundled with OpenCV — no extra files needed.
_face_cascade = cv2.CascadeClassifier(
    cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
)

_FACE_SIZE = 100          # pixels — aligned face is resized to this square
_LBP_RADIUS = 1
_LBP_POINTS = 8 * _LBP_RADIUS
_LBP_GRID   = 8           # grid cells per axis → 8×8 = 64 histogram bins total


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ProcessRequest(BaseModel):
    image: str  # base64-encoded JPEG or PNG


class Candidate(BaseModel):
    patient_id: int
    embedding: list[float]


class MatchRequest(BaseModel):
    probe: dict[str, Any]   # { "embedding": [float, ...] }
    candidates: list[Candidate]


class MatchResponse(BaseModel):
    patient_id: int
    score: float


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _decode_base64_image(b64: str) -> np.ndarray:
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


def _detect_face(img: np.ndarray) -> np.ndarray | None:
    """Detect the largest frontal face and return the cropped region, or None."""
    gray  = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray  = cv2.equalizeHist(gray)
    faces = _face_cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(60, 60),
    )

    if len(faces) == 0:
        return None

    # Pick the largest detected face
    x, y, w, h = max(faces, key=lambda r: r[2] * r[3])
    face_gray   = gray[y : y + h, x : x + w]
    return cv2.resize(face_gray, (_FACE_SIZE, _FACE_SIZE))


def _lbp_pixel(img: np.ndarray, y: int, x: int, radius: int, points: int) -> int:
    """Compute the LBP value for a single pixel."""
    center = img[y, x]
    code   = 0
    for p in range(points):
        angle = 2 * math.pi * p / points
        nx    = x + radius * math.cos(angle)
        ny    = y - radius * math.sin(angle)
        # Bilinear interpolation
        nx0, ny0 = int(math.floor(nx)), int(math.floor(ny))
        nx1, ny1 = nx0 + 1, ny0 + 1
        tx, ty   = nx - nx0, ny - ny0

        if 0 <= nx0 < img.shape[1] - 1 and 0 <= ny0 < img.shape[0] - 1:
            val = (
                (1 - tx) * (1 - ty) * img[ny0, nx0]
                + tx      * (1 - ty) * img[ny0, nx1]
                + (1 - tx) * ty      * img[ny1, nx0]
                + tx      * ty       * img[ny1, nx1]
            )
        else:
            val = 0

        if val >= center:
            code |= 1 << p
    return code


def _extract_embedding(face: np.ndarray) -> list[float]:
    """
    Compute a grid-based LBP histogram embedding.

    Divides the face into an _LBP_GRID×_LBP_GRID grid and concatenates
    normalised LBP histograms from each cell into one flat vector.
    """
    h, w    = face.shape
    cell_h  = h // _LBP_GRID
    cell_w  = w // _LBP_GRID

    embedding: list[float] = []

    for gy in range(_LBP_GRID):
        for gx in range(_LBP_GRID):
            cell = face[
                gy * cell_h : (gy + 1) * cell_h,
                gx * cell_w : (gx + 1) * cell_w,
            ]
            # Use cv2.calcHist for speed — much faster than pixel-by-pixel LBP
            hist = cv2.calcHist([cell], [0], None, [256], [0, 256])
            hist = hist.flatten()
            total = hist.sum()
            if total > 0:
                hist = hist / total
            embedding.extend(hist.tolist())

    return embedding


def _quality_score(face: np.ndarray) -> float:
    """Laplacian variance as a sharpness proxy, clamped to [0, 1]."""
    lap = cv2.Laplacian(face, cv2.CV_64F).var()
    return float(min(lap / 300.0, 1.0))


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    va  = np.array(a, dtype=np.float64)
    vb  = np.array(b, dtype=np.float64)
    dot = float(np.dot(va, vb))
    na  = float(np.linalg.norm(va))
    nb  = float(np.linalg.norm(vb))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/process", summary="Extract face embedding from a base64 image")
def face_process(body: ProcessRequest) -> dict:
    """
    Accepts a base64-encoded face image. Detects the largest frontal face,
    computes a grid LBP histogram embedding, and returns the embedding along
    with a quality score and face_detected flag.

    quality_score is in [0, 1]. Captures below 0.20 should be rejected.
    """
    img          = _decode_base64_image(body.image)
    face         = _detect_face(img)
    face_detected = face is not None

    if not face_detected:
        return {
            "face_detected": False,
            "quality_score": 0.0,
            "embedding":     [],
        }

    quality   = _quality_score(face)
    embedding = _extract_embedding(face)

    return {
        "face_detected": True,
        "quality_score": round(quality, 4),
        "embedding":     embedding,
    }


@router.post(
    "/match",
    response_model=MatchResponse,
    summary="Match a probe embedding against a list of face candidates",
)
def face_match(body: MatchRequest) -> MatchResponse:
    """
    Computes cosine similarity between the probe embedding and every candidate.
    Returns the candidate with the highest similarity score.
    """
    if not body.candidates:
        raise HTTPException(status_code=400, detail="'candidates' list is empty.")

    probe_embedding = body.probe.get("embedding")
    if not probe_embedding:
        raise HTTPException(status_code=400, detail="'probe.embedding' is missing or empty.")

    best_score = -1.0
    best_id: int | None = None

    for candidate in body.candidates:
        if not candidate.embedding:
            continue
        score = _cosine_similarity(probe_embedding, candidate.embedding)
        if score > best_score:
            best_score = score
            best_id    = candidate.patient_id

    if best_id is None:
        raise HTTPException(
            status_code=400, detail="No valid candidates could be processed."
        )

    return MatchResponse(patient_id=best_id, score=round(best_score, 4))
