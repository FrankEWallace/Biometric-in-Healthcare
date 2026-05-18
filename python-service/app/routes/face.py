"""
Face recognition endpoints — InsightFace ArcFace + FAISS.

POST /face/process          base64 image → ArcFace embedding + quality score
POST /face/identify         embedding → top-N patient candidates (FAISS search)
POST /face/enroll           add one embedding to the FAISS index
POST /face/remove           logically delete all embeddings for a patient
POST /face/rebuild          rebuild the FAISS index from a full template list
GET  /face/index/stats      FAISS index health statistics
POST /face/match            probe embedding + candidate list → best match (1:1 cosine)
"""
from __future__ import annotations

import base64
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.insightface_service import detect_and_embed
from app.services import faiss_service

router = APIRouter(prefix="/face", tags=["face"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class ProcessRequest(BaseModel):
    image: str  # base64 JPEG or PNG


class IdentifyRequest(BaseModel):
    embedding: list[float]
    top_k: int = 5


class EnrollRequest(BaseModel):
    patient_id:  int
    template_id: int
    embedding:   list[float]


class RemoveRequest(BaseModel):
    patient_id: int


class RebuildItem(BaseModel):
    patient_id:  int
    template_id: int
    embedding:   list[float]


class RebuildRequest(BaseModel):
    templates: list[RebuildItem]


class MatchCandidate(BaseModel):
    patient_id: int
    embedding:  list[float]


class MatchRequest(BaseModel):
    probe:      dict[str, Any]   # {"embedding": [...]}
    candidates: list[MatchCandidate]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _decode_image(b64: str) -> np.ndarray:
    try:
        buf = np.frombuffer(base64.b64decode(b64), dtype=np.uint8)
    except Exception as exc:
        raise HTTPException(400, f"Invalid base64 data: {exc}")
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(400, "Could not decode image. Send a valid JPEG or PNG.")
    return img


def _cosine(a: list[float], b: list[float]) -> float:
    va = np.array(a, dtype=np.float64)
    vb = np.array(b, dtype=np.float64)
    na, nb = float(np.linalg.norm(va)), float(np.linalg.norm(vb))
    return float(np.dot(va, vb) / (na * nb)) if na > 0 and nb > 0 else 0.0


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/process", summary="Extract ArcFace embedding from a base64 image")
def face_process(body: ProcessRequest) -> dict:
    """
    Detect the largest face and return its 512-dim ArcFace embedding.
    quality_score is InsightFace detection confidence [0, 1].
    Callers should reject captures where quality_score < 0.50.
    """
    img = _decode_image(body.image)
    return detect_and_embed(img)


@router.post("/identify", summary="Identify top-N patients by face embedding (FAISS)")
def face_identify(body: IdentifyRequest) -> dict:
    """
    Search the in-memory FAISS index for the closest patient embeddings.
    Returns up to top_k candidates sorted by cosine similarity (descending).
    """
    if not body.embedding:
        raise HTTPException(400, "'embedding' must not be empty.")
    candidates = faiss_service.identify(body.embedding, top_k=body.top_k)
    return {"candidates": candidates}


@router.post("/enroll", summary="Add an embedding to the FAISS index")
def face_enroll(body: EnrollRequest) -> dict:
    """Called by Laravel immediately after storing a new FaceTemplate row."""
    if not body.embedding:
        raise HTTPException(400, "'embedding' must not be empty.")
    pos = faiss_service.enroll(body.patient_id, body.template_id, body.embedding)
    return {"success": True, "position": pos}


@router.post("/remove", summary="Remove all embeddings for a patient from FAISS")
def face_remove(body: RemoveRequest) -> dict:
    """Called by Laravel when a patient's face templates are deactivated or deleted."""
    count = faiss_service.remove_patient(body.patient_id)
    return {"removed_count": count}


@router.post("/rebuild", summary="Rebuild the FAISS index from a full template list")
def face_rebuild(body: RebuildRequest) -> dict:
    """
    Replaces the current index entirely.  Payload must contain all active
    templates.  Called after bulk migrations or when the index file is lost.
    """
    templates = [t.model_dump() for t in body.templates]
    count = faiss_service.rebuild(templates)
    return {"indexed_count": count}


@router.get("/index/stats", summary="FAISS index health statistics")
def face_index_stats() -> dict:
    return faiss_service.stats()


@router.post("/match", summary="1:1 cosine similarity match (verification stage)")
def face_match(body: MatchRequest) -> dict:
    """
    Kept for backward compatibility and 1:1 verification use cases.
    Scores the probe against a small explicit candidate list rather than
    searching the full FAISS index.
    """
    probe_emb = body.probe.get("embedding")
    if not probe_emb:
        raise HTTPException(400, "'probe.embedding' is missing.")
    if not body.candidates:
        raise HTTPException(400, "'candidates' is empty.")

    best_score, best_id = -1.0, None
    for c in body.candidates:
        if not c.embedding:
            continue
        s = _cosine(probe_emb, c.embedding)
        if s > best_score:
            best_score, best_id = s, c.patient_id

    if best_id is None:
        raise HTTPException(400, "No valid candidates could be processed.")

    return {"patient_id": best_id, "score": round(best_score, 4)}
