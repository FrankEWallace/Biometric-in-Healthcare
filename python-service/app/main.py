"""
Biometric Microservice — FastAPI entry point.

Consumed internally by the Laravel backend only.
Not exposed to the public internet.

Endpoints:
  GET  /health                        — liveness probe
  POST /process                       — fingerprint base64 image → minutiae template
  POST /match                         — fingerprint probe + candidates → best match
  POST /fingerprint/liveness-check    — frame sequence → optical-flow liveness verdict
  POST /face/process                  — face base64 image → ArcFace embedding
  POST /face/liveness                 — face base64 image → passive liveness check
  POST /face/identify                 — embedding → top-N candidates (FAISS)
  POST /face/enroll                   — add embedding to FAISS index
  POST /face/remove                   — remove patient from FAISS index
  POST /face/rebuild                  — rebuild FAISS from full template list
  GET  /face/index/stats              — FAISS health check

Interactive docs: http://localhost:5001/docs
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.routes.face import router as face_router
from app.routes.fingerprint import router as fingerprint_router
from app.routes.health import router as health_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Pre-load InsightFace model and FAISS index at startup so the first
    # real request is not penalised by cold-load latency (~2–5 s on CPU).
    try:
        from app.services.insightface_service import warmup as face_warmup
        face_warmup()
    except Exception as exc:
        logger.warning("InsightFace warmup skipped: %s", exc)

    try:
        from app.services.faiss_service import initialise as faiss_init
        faiss_init()
    except Exception as exc:
        logger.warning("FAISS init skipped: %s", exc)

    yield


app = FastAPI(
    title="Biometric Processing Service",
    description=(
        "InsightFace ArcFace + FAISS face identification "
        "and minutiae-based contactless fingerprint verification."
    ),
    version="3.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.include_router(health_router)
app.include_router(fingerprint_router)
app.include_router(face_router)
