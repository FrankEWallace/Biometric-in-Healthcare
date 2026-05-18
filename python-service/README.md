# BiH Fingerprint System — Python Microservice

FastAPI microservice responsible for all biometric processing: fingerprint image preprocessing, minutiae template extraction, fingerprint matching, face detection, and face embedding. Consumed exclusively by the Laravel backend — never exposed directly to the mobile client.

---

## Overview

The service sits between the Laravel API and raw biometric images. Laravel sends images or templates; this service returns extracted features, quality scores, and match verdicts. Keeping processing here isolates the computationally expensive OpenCV work from the PHP process and keeps the matching logic in one testable place.

```
Flutter App  →  Laravel API  →  Python Microservice (localhost:5001)
                                      ↓
                                  MySQL (via Laravel)
```

---

## Requirements

| Dependency | Version |
|------------|---------|
| Python | 3.11 – 3.12 (see note below) |
| pip / venv | any recent |

> **Python 3.13+**: The `sourceafis` pip package requires Python ≤ 3.12. This service uses a native OpenCV crossing-number minutiae implementation as a drop-in replacement, so Python 3.13 works fine. The `sourceafis_service.py` module name is kept for API stability.

---

## Setup

```bash
cd python-service

# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate      # macOS / Linux
# .venv\Scripts\activate       # Windows

# Install dependencies
pip install -r requirements.txt

# Start the service
python run.py
```

The service starts on `http://localhost:5001`.
Interactive API docs: `http://localhost:5001/docs`

---

## Configuration

The only configurable value at startup is the port and host in `run.py`:

```python
uvicorn.run(
    "app.main:app",
    host="0.0.0.0",     # bind to 127.0.0.1 in production
    port=5001,
    reload=False,        # set True during development
)
```

In production, bind to `127.0.0.1` so the service is only reachable from Laravel on the same host.

---

## Dependencies

```
fastapi>=0.115         Web framework and request routing
uvicorn[standard]>=0.30  ASGI server
opencv-python>=4.9     Image processing, ORB feature detection
numpy>=1.26            Array operations
pillow>=10.0           Image I/O helpers
python-multipart>=0.0.9  Multipart file upload support
```

---

## Directory Structure

```
python-service/
├── app/
│   ├── main.py              FastAPI app instance and router registration
│   ├── routes/
│   │   ├── fingerprint.py   Fingerprint processing and matching endpoints
│   │   ├── face.py          Face detection and embedding endpoints
│   │   └── health.py        Health check endpoint
│   └── services/
│       ├── image_processor.py    Preprocessing pipeline (grayscale → skeleton)
│       ├── feature_extractor.py  ORB keypoint detection and BFMatcher
│       ├── minutiae_service.py   Crossing-number minutiae algorithm
│       ├── sourceafis_service.py Template extraction/matching API (wraps minutiae_service)
│       └── processor.py          Utility helpers
├── requirements.txt
└── run.py                   Entry point
```

---

## API Reference

All endpoints are prefixed at the root (`/`). No authentication — the service must not be reachable outside the host machine.

### Health

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Returns `{ "status": "ok" }` |

---

### Fingerprint

#### `POST /process`
Extract a SourceAFIS-compatible minutiae template from a **base64-encoded** image.

**Request**
```json
{
  "image": "<base64-encoded JPEG or PNG>"
}
```

**Response**
```json
{
  "template": { "minutiae_count": 42, "data": [...], "format": "minutiae", "status": "ok" },
  "quality_score": 0.83
}
```

Used by `VerificationController` for hospital-wide identification scans.

---

#### `POST /match`
Match a probe template against a list of candidate templates. Returns the candidate with the highest minutiae score.

**Request**
```json
{
  "probe": { "<template dict>" },
  "candidates": [
    { "patient_id": 1, "template": { "<template dict>" } }
  ]
}
```

**Response**
```json
{
  "patient_id": 1,
  "score": 54.23
}
```

Score range: 0–100 (crossing-number minutiae algorithm). Recommended match threshold: **20**. Calibrate using FAR/FRR measurements on your capture hardware.

---

#### `POST /process-fingerprint`
Multipart upload variant of `/process`. Returns full pipeline detail including preprocessing steps, the processed skeleton image, and feature status.

**Request**: `multipart/form-data` with field `file` (JPEG or PNG).

**Response**
```json
{
  "success": true,
  "message": "Image processed successfully.",
  "filename": "finger.jpg",
  "quality_score": 0.76,
  "steps_applied": ["grayscale", "blur", "equalize", "threshold", "thin"],
  "processed_image": "<base64 skeleton PNG>",
  "features": {
    "minutiae_count": 38,
    "status": "ok",
    "format": "minutiae",
    "data": [...],
    "keypoint_count": 38
  }
}
```

Feature `status` values:
| Value | Meaning |
|-------|---------|
| `ok` | Sufficient minutiae for reliable matching (≥10) |
| `low_quality` | Fewer than 10 minutiae; match result unreliable |
| `no_features` | Blank or unreadable image; reject the capture |

---

#### `POST /match-fingerprint`
Direct image-to-image comparison. Preprocesses both uploads, extracts templates, and returns a verdict.

**Request**: `multipart/form-data` with fields `image1` and `image2`.

**Response**
```json
{
  "verdict": "MATCH",
  "score": 61.5,
  "image1": { "filename": "a.jpg", "minutiae_count": 40, "feature_status": "ok" },
  "image2": { "filename": "b.jpg", "minutiae_count": 37, "feature_status": "ok" }
}
```

Verdict threshold: score ≥ **40** → MATCH.

---

### Face

#### `POST /face/process`
Detect the largest frontal face in a base64 image and return an LBP histogram embedding.

**Request**
```json
{
  "image": "<base64-encoded JPEG or PNG>"
}
```

**Response**
```json
{
  "face_detected": true,
  "quality_score": 0.71,
  "embedding": [0.003, 0.012, ...]
}
```

Quality score is a Laplacian variance sharpness measure in [0, 1]. Captures below **0.20** should be rejected. The embedding is a grid-LBP histogram vector (64 cells × 256 bins = 16 384 floats).

---

#### `POST /face/match`
Match a probe embedding against a list of face candidates using cosine similarity.

**Request**
```json
{
  "probe": { "embedding": [0.003, 0.012, ...] },
  "candidates": [
    { "patient_id": 7, "embedding": [0.004, 0.011, ...] }
  ]
}
```

**Response**
```json
{
  "patient_id": 7,
  "score": 0.9421
}
```

Score range: −1 to 1 (cosine similarity). Higher is more similar.

---

## Processing Pipeline

### Fingerprint

```
Raw image (JPEG/PNG)
    → Grayscale conversion
    → Gaussian blur (noise reduction)
    → Histogram equalization (contrast normalisation)
    → Adaptive threshold (binarization)
    → Morphological thinning (skeleton)
    → Crossing-number minutiae detection
    → Template dict  { minutiae_count, data, format, status }
```

### Face

```
Raw image (JPEG/PNG)
    → Grayscale + histogram equalization
    → Haar cascade face detection (largest face selected)
    → Resize to 100×100 px
    → Grid-LBP histogram (8×8 grid, 256-bin histograms)
    → Normalised flat embedding vector
```

---

## Matching Thresholds

| Biometric | Algorithm | Match Threshold | Score Range |
|-----------|-----------|-----------------|-------------|
| Fingerprint (enrollment/verification) | Crossing-number minutiae | 20 | 0–100 |
| Fingerprint (direct image comparison) | Same | 40 | 0–100 |
| Face | Cosine similarity (LBP) | N/A (returned to caller) | −1 to 1 |

These defaults are conservative starting points. Adjust after measuring false accept rate (FAR) and false reject rate (FRR) on your specific fingerprint sensor and patient population.

---

## Production Notes

- Bind to `127.0.0.1` — this service has no authentication and must not be internet-accessible.
- Set `reload=False` in `run.py` (already the default) in production.
- The face embedding (LBP histogram) is lightweight and suitable for MVP use. Swap `_extract_embedding()` in `face.py` for DeepFace or InsightFace embeddings to improve accuracy when those dependencies become available.
- Raw fingerprint images are never persisted here. Only the template dict (minutiae positions and orientations) leaves the service and is stored by Laravel — encrypted via Laravel `Crypt`.
