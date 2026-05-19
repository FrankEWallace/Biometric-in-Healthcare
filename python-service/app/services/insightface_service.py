"""
InsightFace ArcFace embedding service.

Loads the buffalo_s model pack once at first call and reuses it for the
process lifetime.  buffalo_s (~60 MB) is the recommended choice for
CPU-only deployments with hospital-scale patient counts (hundreds–thousands).
Switch to buffalo_l for GPU-equipped servers where accuracy is critical.

Model files are downloaded automatically to ~/.insightface/models/ on first
use.  Run `python -c "from app.services.insightface_service import warmup; warmup()"
once after pip install to pre-download during deployment.
"""
from __future__ import annotations

import logging

import numpy as np

logger = logging.getLogger(__name__)

_face_app = None
_MODEL_NAME = "buffalo_s"


def _get_app():
    global _face_app
    if _face_app is not None:
        return _face_app

    try:
        from insightface.app import FaceAnalysis
        app = FaceAnalysis(name=_MODEL_NAME, providers=["CPUExecutionProvider"])
        app.prepare(ctx_id=0, det_size=(640, 640))
        _face_app = app
        logger.info("InsightFace %s loaded.", _MODEL_NAME)
    except Exception as exc:
        logger.error("InsightFace failed to load: %s", exc)
        raise

    return _face_app


def warmup() -> None:
    """Pre-load the model.  Call once at service startup."""
    _get_app()


def detect_and_embed(image_bgr: np.ndarray) -> dict:
    """
    Detect the largest face in the image and return its ArcFace embedding.

    Returns:
        {
            "face_detected": bool,
            "embedding":     list[float],   # 512-dim ArcFace vector; [] if no face
            "quality_score": float,         # InsightFace detection confidence [0, 1]
            "bbox":          list[float] | None,
        }
    """
    app   = _get_app()
    faces = app.get(image_bgr)

    if not faces:
        return {"face_detected": False, "embedding": [], "quality_score": 0.0, "bbox": None}

    face = max(faces, key=lambda f: float(f.det_score))

    if face.embedding is None:
        return {"face_detected": False, "embedding": [], "quality_score": 0.0, "bbox": None}

    return {
        "face_detected": True,
        "embedding":     face.embedding.tolist(),
        "quality_score": round(float(face.det_score), 4),
        "bbox":          [round(float(x), 1) for x in face.bbox],
    }
