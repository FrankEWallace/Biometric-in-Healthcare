"""
Learned contactless-fingerprint embedding matcher (Phase 3).

Motivation
----------
Minutiae matching is near-random on contactless finger photos (RidgeBase CL2CL
EER ~46%; even VeriFinger caps ~20%). The contactless field uses **learned deep
embeddings** instead — a network maps a finger photo to a fixed-length vector,
and identity is cosine similarity between vectors. The SOTA on RidgeBase is
Ridgeformer (arXiv:2506.01806): CL2CL EER 7.6%, C2CL 5.25%.

Phase 3 spike findings (2026-07-05)
-----------------------------------
* Ridgeformer weights ARE publicly released (Google Drive + HuggingFace) — repo
  github.com/KNITPhoenix/Ridgeformer.
* Framework is PyTorch; licence is CC-BY-NC 4.0 (academic / non-commercial —
  fine for the FYP, a constraint for any commercial deployment).
* Serving path chosen for THIS service: export the encoder to **ONNX** and run
  it with ``onnxruntime`` — exactly how InsightFace already runs here (CPU, no
  torch at serve time). Keeps the service dependency-light and offline-capable.

Status
------
This class is the *integration point*, wired behind the ``Matcher`` interface
so the four-finger pipeline runs end-to-end today on the minutiae placeholder
and swaps to the embedding the moment a model file is dropped in. It is
**inactive until a model is installed** — ``available`` is False with no model,
and ``get_matcher("contactless")`` transparently falls back to minutiae.

To activate:
  1. Export Ridgeformer's contactless encoder to ONNX (opset ≥ 17), single
     image input, L2-normalised embedding output.
  2. Save it to ``EMBEDDING_MODEL_PATH`` (env) or ``models/contactless_embedding.onnx``.
  3. Confirm ``INPUT_SIZE`` / normalisation below match the exported model's
     training preprocessing, then re-run ``tools/ridgebase_eval.py`` to
     calibrate the contactless threshold from *these* numbers.
"""

from __future__ import annotations

import os
from typing import Any

import cv2
import numpy as np

from app.services.matcher import Matcher

# Default location; override with EMBEDDING_MODEL_PATH.
_DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
    "models",
    "contactless_embedding.onnx",
)


class EmbeddingUnavailableError(RuntimeError):
    """Raised when an embedding operation is attempted with no model loaded."""


class EmbeddingMatcher(Matcher):
    """
    ONNX-served contactless embedding matcher.

    Produces ``{"format": "embedding", "vector": [...], "dim": N}`` templates
    and scores them by cosine similarity mapped to [0, 100]. Lazy-loads the
    ONNX session on first use so importing this module is cheap and never fails
    just because the model file is absent.
    """

    name = "onnx-contactless-embedding"
    domain = "contactless"
    template_format = "embedding"

    # Matches the exported Ridgeformer encoder's training transform (RB_loader
    # test transform): resize 224, grayscale→3ch, /255, NO ImageNet mean/std.
    # Verified: this preprocessing reproduces the torch reference embedding at
    # cosine ≥0.997 (INTER_AREA downsample). See docs ridgeformer_eval.md.
    INPUT_SIZE = (224, 224)

    def __init__(self, model_path: str | None = None):
        self.model_path = model_path or _DEFAULT_MODEL_PATH
        self._session = None  # lazy onnxruntime.InferenceSession
        self._input_name: str | None = None

    @classmethod
    def from_env(cls) -> "EmbeddingMatcher":
        return cls(os.environ.get("EMBEDDING_MODEL_PATH"))

    # -- lifecycle ---------------------------------------------------------

    @property
    def available(self) -> bool:
        return bool(self.model_path) and os.path.exists(self.model_path)

    def _ensure_session(self) -> None:
        if self._session is not None:
            return
        if not self.available:
            raise EmbeddingUnavailableError(
                f"No contactless embedding model at {self.model_path!r}. "
                "Install one (see embedding_service.py header) or rely on the "
                "minutiae fallback."
            )
        import onnxruntime as ort  # imported lazily; already a service dep

        self._session = ort.InferenceSession(
            self.model_path, providers=["CPUExecutionProvider"]
        )
        self._input_name = self._session.get_inputs()[0].name

    # -- preprocessing -----------------------------------------------------

    def _preprocess(self, image_bgr: np.ndarray, hand: str | None = None) -> np.ndarray:
        """
        Match the model's training transform exactly.

        Optional ``hand`` applies RB_loader's orientation normalisation (RIGHT:
        rotate 90° CW + horizontal flip; LEFT: 90° CCW + flip) so captures match
        the pose the encoder was trained on. Grayscale uses torchvision's RGB
        weights on the cv2 BGR-ordered channels — replicating how RB_loader
        feeds cv2 images straight into ToTensor+Grayscale without a channel swap.
        """
        img = image_bgr
        if hand is not None:
            if str(hand).lower().startswith("r"):
                img = cv2.flip(cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE), 1)
            else:
                img = cv2.flip(cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE), 1)

        # INTER_AREA matches torchvision's antialiased downsample (cosine ≥0.997
        # vs the torch reference; plain INTER_LINEAR only ~0.987).
        img = cv2.resize(img, self.INPUT_SIZE, interpolation=cv2.INTER_AREA)
        b = img[..., 0].astype(np.float32)
        g = img[..., 1].astype(np.float32)
        r = img[..., 2].astype(np.float32)
        gray = np.clip(0.2989 * b + 0.587 * g + 0.114 * r, 0, 255) / 255.0
        chw = np.stack([gray, gray, gray], axis=0)  # 3 identical channels, CHW
        return chw[np.newaxis, ...].astype(np.float32)  # NCHW

    # -- Matcher API -------------------------------------------------------

    def extract(
        self, image_bgr: np.ndarray, *, enhance: bool = True, hand: str | None = None
    ) -> dict[str, Any]:
        self._ensure_session()
        tensor = self._preprocess(image_bgr, hand=hand)
        outputs = self._session.run(None, {self._input_name: tensor})
        vec = np.asarray(outputs[0], dtype=np.float32).ravel()
        norm = float(np.linalg.norm(vec))
        if norm > 0:
            vec = vec / norm  # L2-normalise so cosine == dot product
        return {"format": "embedding", "vector": vec.tolist(), "dim": int(vec.size)}

    def score(self, probe: dict[str, Any], candidate: dict[str, Any]) -> float:
        self._assert_format(probe)
        self._assert_format(candidate)
        a = np.asarray(probe.get("vector", []), dtype=np.float32)
        b = np.asarray(candidate.get("vector", []), dtype=np.float32)
        if a.size == 0 or a.size != b.size:
            return 0.0
        # Both are L2-normalised, so dot == cosine in [-1, 1]. Map to [0, 100].
        cos = float(np.dot(a, b))
        return max(0.0, cos) * 100.0
