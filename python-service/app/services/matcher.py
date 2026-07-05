"""
Pluggable, domain-routed fingerprint matcher interface.

Why this exists
---------------
Calibration on RidgeBase proved the crossing-number **minutiae** matcher is
strong on contact prints (SOCOFing EER 13.5%) but near-random on contactless
finger *photos* (EER ~46%, i.e. coin-flip). The fix is not to replace the
matcher but to *route by domain*:

    contact  ↔ contact      → minutiae (ISO-19794-2, explainable, NIDA/AFIS-interoperable)
    contactless / C2CL      → a learned embedding (the only thing that works on photos)

This module defines the abstraction that lets the rest of the service stay
matcher-agnostic. The four-finger enroll/verify flow, the FastAPI routes, and
the calibration harness all talk to a ``Matcher``; swapping the contactless
implementation (Phase 3, see ``embedding_service.py``) changes accuracy without
touching any caller.

A ``Matcher`` is two primitives plus metadata:

    extract(image_bgr, enhance=...) -> template dict   (opaque to callers)
    score(probe_template, candidate_template) -> float in [0, 100]

Templates are JSON-serialisable dicts so Laravel can encrypt and store them
unchanged. The ``format`` key distinguishes representations (``"minutiae"`` vs
``"embedding"``); a matcher only scores templates of its own format.

Four-finger fusion
------------------
A phone photo of a hand yields up to 4 finger crops. ``match_hands`` matches
each shared finger position and fuses the per-finger scores (mean by default),
the same logic validated in ``tools/ridgebase_eval.py``. Fusion reduces score
noise by ~√N — a multiplier on an already-good per-finger matcher, not a rescue
for a bad one (measured: minutiae four-finger EER still ~42%).
"""

from __future__ import annotations

import base64
import os
from abc import ABC, abstractmethod
from typing import Any

import cv2
import numpy as np

from app.services.image_processor import preprocess_fingerprint
from app.services.sourceafis_service import extract_template, match_templates


# ---------------------------------------------------------------------------
# Finger-position vocabulary (mirrors the Laravel finger_position enum)
# ---------------------------------------------------------------------------

# A four-finger "slap" is the four non-thumb fingers of one hand — the
# IDEMIA 4F convention. The thumb is captured separately or skipped.
RIGHT_HAND_FINGERS = ("right_index", "right_middle", "right_ring", "right_little")
LEFT_HAND_FINGERS = ("left_index", "left_middle", "left_ring", "left_little")


def hand_fingers(hand: str) -> tuple[str, ...]:
    """Ordered finger positions for ``hand`` in ("right" | "left")."""
    h = hand.strip().lower()
    if h in ("right", "right_hand"):
        return RIGHT_HAND_FINGERS
    if h in ("left", "left_hand"):
        return LEFT_HAND_FINGERS
    raise ValueError(f"hand must be 'right' or 'left', got {hand!r}")


# ---------------------------------------------------------------------------
# Matcher abstraction
# ---------------------------------------------------------------------------

class Matcher(ABC):
    """A fingerprint feature extractor + comparator for one domain."""

    #: Human-readable identifier, logged with results for reproducibility.
    name: str = "abstract"

    #: "contact" | "contactless" — which capture domain this matcher is for.
    domain: str = "contact"

    #: Template ``format`` tag this matcher produces and can score.
    template_format: str = "abstract"

    @property
    def available(self) -> bool:
        """
        Whether this matcher can actually run right now (weights present,
        deps importable, ...). The minutiae matcher is always available; the
        embedding matcher is only available once its model file is installed.
        """
        return True

    @abstractmethod
    def extract(self, image_bgr: np.ndarray, *, enhance: bool = True) -> dict[str, Any]:
        """Build a template from a single-finger BGR image."""

    @abstractmethod
    def score(self, probe: dict[str, Any], candidate: dict[str, Any]) -> float:
        """Compare two templates of this matcher's format. Returns [0, 100]."""

    def _assert_format(self, template: dict[str, Any]) -> None:
        fmt = template.get("format")
        if fmt is not None and fmt != self.template_format:
            raise ValueError(
                f"{self.name} cannot score a '{fmt}' template "
                f"(expects '{self.template_format}')."
            )


class MinutiaeMatcher(Matcher):
    """
    Crossing-number minutiae matcher (the current production matcher).

    Registered as the **contact** implementation and used as the safe default
    everywhere until the embedding matcher is installed. Wraps the existing
    ``image_processor`` preprocessing + ``sourceafis_service`` extract/match so
    behaviour is identical to the single-finger ``/process`` + ``/match`` path.
    """

    name = "minutiae-crossing-number"
    domain = "contact"
    template_format = "minutiae_v1"  # matches minutiae_service.template_to_dict

    def extract(self, image_bgr: np.ndarray, *, enhance: bool = True) -> dict[str, Any]:
        pre = preprocess_fingerprint(image_bgr, enhance=enhance)
        skeleton_bytes = base64.b64decode(pre["processed_image"])
        skeleton = cv2.imdecode(
            np.frombuffer(skeleton_bytes, dtype=np.uint8), cv2.IMREAD_GRAYSCALE
        )
        if skeleton is None:
            raise RuntimeError("preprocessing produced an unreadable skeleton")

        template = extract_template(skeleton)
        # Carry capture quality on the template so callers (enroll gating,
        # per-finger quality reporting) don't need a second pass.
        template["quality_score"] = float(pre["quality_score"])
        return template

    def score(self, probe: dict[str, Any], candidate: dict[str, Any]) -> float:
        self._assert_format(probe)
        self._assert_format(candidate)
        return float(match_templates(probe, candidate))


# ---------------------------------------------------------------------------
# Score fusion + hand-level matching
# ---------------------------------------------------------------------------

def fuse_scores(scores: list[float], method: str = "mean") -> float:
    """
    Combine per-finger scores into one hand score.

    mean — average (default; ~√N noise reduction, the validated choice).
    max  — most-confident finger (permissive; raises FAR).
    min  — least-confident finger (strict; raises FRR).
    """
    if not scores:
        return 0.0
    if method == "mean":
        return sum(scores) / len(scores)
    if method == "max":
        return max(scores)
    if method == "min":
        return min(scores)
    raise ValueError(f"unknown fusion method {method!r}")


def match_hands(
    probe: dict[str, dict[str, Any]],
    candidate: dict[str, dict[str, Any]],
    *,
    matcher: Matcher,
    min_fingers: int = 3,
    fusion: str = "mean",
) -> tuple[float, list[str], dict[str, float]]:
    """
    Match two hands (finger_position -> template) and fuse the shared fingers.

    Only positions present in BOTH hands are scored, mirroring the harness:
    if fewer than ``min_fingers`` overlap, the hands are not comparable and the
    fused score is 0.0 (caller treats as no-match rather than a false accept).

    Returns ``(fused_score, fingers_used, per_finger_scores)``.
    """
    shared = sorted(set(probe) & set(candidate))
    per_finger: dict[str, float] = {}
    for pos in shared:
        per_finger[pos] = matcher.score(probe[pos], candidate[pos])

    if len(per_finger) < min_fingers:
        return 0.0, list(per_finger.keys()), per_finger

    fused = fuse_scores(list(per_finger.values()), method=fusion)
    return fused, list(per_finger.keys()), per_finger


# ---------------------------------------------------------------------------
# Registry — domain-routed matcher selection
# ---------------------------------------------------------------------------

_REGISTRY: dict[str, Matcher] = {}


def register_matcher(matcher: Matcher, *, domains: tuple[str, ...] | None = None) -> None:
    """Register ``matcher`` under one or more domain keys."""
    for domain in (domains or (matcher.domain,)):
        _REGISTRY[domain] = matcher


def get_matcher(domain: str = "contact") -> Matcher:
    """
    Return the matcher for ``domain`` ("contact" | "contactless").

    Routing rules:
      * ``FINGERPRINT_MATCHER=minutiae`` forces the minutiae matcher for every
        domain (used to reproduce the pure-minutiae baseline).
      * Otherwise return the registered matcher for the domain, **falling back
        to minutiae** if the domain's matcher is not yet available (e.g. the
        embedding model isn't installed). The fallback is logged via the
        returned matcher's ``name`` so callers can surface "running on
        placeholder" in results.
    """
    forced = os.environ.get("FINGERPRINT_MATCHER", "").strip().lower()
    if forced == "minutiae":
        return _REGISTRY["contact"]

    matcher = _REGISTRY.get(domain) or _REGISTRY["contact"]
    if not matcher.available:
        return _REGISTRY["contact"]
    return matcher


# Contact matcher is always available and is the default fallback.
register_matcher(MinutiaeMatcher(), domains=("contact",))

# The contactless embedding matcher registers itself on import (guarded so an
# absent model degrades to the minutiae fallback rather than crashing).
try:  # pragma: no cover - optional Phase 3 dependency
    from app.services.embedding_service import EmbeddingMatcher

    register_matcher(EmbeddingMatcher.from_env(), domains=("contactless",))
except Exception:  # noqa: BLE001 - embedding path is optional until Phase 3 lands
    # No embedding matcher available: contactless requests fall back to
    # minutiae via get_matcher()'s availability check.
    pass
