"""
Fingerprint Microservice — FastAPI entry point.

Consumed internally by the Laravel backend only.
Not exposed to the public internet.

Endpoints:
  GET  /health   — liveness probe
  POST /process  — base64 image → ORB template + quality score
  POST /match    — probe template + candidates → best patient_id + score

Interactive docs available at:
  http://localhost:5001/docs   (Swagger UI)
  http://localhost:5001/redoc  (ReDoc)
"""

from fastapi import FastAPI

from app.routes.health import router as health_router
from app.routes.fingerprint import router as fingerprint_router

app = FastAPI(
    title="Fingerprint Processing Service",
    description="OpenCV-based ORB fingerprint feature extraction and matching.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.include_router(health_router)
app.include_router(fingerprint_router)
