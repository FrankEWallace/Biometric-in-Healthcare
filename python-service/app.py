"""
Python OpenCV Microservice
--------------------------
Consumed internally by the Laravel backend only.
Exposes three endpoints:

  POST /process   — base64 image → ORB template (JSON)
  POST /match     — probe template + candidates → best score + patient_id
  GET  /health    — liveness check
"""

import base64

import cv2
import numpy as np
from flask import Flask, jsonify, request

from processor import build_template, match_templates

app = Flask(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _decode_image(b64: str) -> np.ndarray:
    image_bytes = base64.b64decode(b64)
    buf = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image from base64 data.")
    return img


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/process")
def process():
    """
    Request:  { "image": "<base64>" }
    Response: { "template": { "keypoints": [...], "descriptors": [[...]] },
                "quality_score": 0.742 }
    """
    body = request.get_json(force=True, silent=True) or {}
    if "image" not in body:
        return jsonify({"error": "Missing 'image' field."}), 400

    try:
        image = _decode_image(body["image"])
    except Exception as exc:
        return jsonify({"error": f"Image decoding failed: {exc}"}), 400

    result = build_template(image)
    return jsonify(result)  # { "template": {...}, "quality_score": float }


@app.post("/match")
def match():
    """
    Request:
    {
        "probe": { "keypoints": [...], "descriptors": [[...]] },
        "candidates": [
            { "patient_id": 1, "template": { ... } },
            ...
        ]
    }
    Response: { "patient_id": 1, "score": 0.87 }
    """
    body = request.get_json(force=True, silent=True) or {}
    probe = body.get("probe")
    candidates = body.get("candidates")

    if not probe:
        return jsonify({"error": "Missing 'probe' field."}), 400
    if not isinstance(candidates, list) or not candidates:
        return jsonify({"error": "Missing or empty 'candidates' list."}), 400

    best_score = -1.0
    best_id = None

    for entry in candidates:
        tmpl = entry.get("template")
        if tmpl is None:
            continue
        score = match_templates(probe, tmpl)
        if score > best_score:
            best_score = score
            best_id = entry.get("patient_id")

    if best_id is None:
        return jsonify({"error": "No valid candidates found."}), 400

    return jsonify({"patient_id": best_id, "score": best_score})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)
