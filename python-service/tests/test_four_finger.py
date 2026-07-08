"""
Four-finger pipeline tests: matcher interface, fusion, segmentation, endpoints.

Runnable via pytest without the (gitignored) RidgeBase dataset — the
dataset-dependent tests (self-match == 100 on real ridges) are skipped with a
reason when the data isn't present, so this suite passes in CI too.

    python -m pytest tests/test_four_finger.py
"""
from __future__ import annotations

import base64
import re
import sys
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np
import pytest

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from app.routes.hand import (  # noqa: E402
    CandidateHand, MatchHandRequest, ProcessHandRequest, match_hand, process_hand,
)
from app.services.hand_segmentation import (  # noqa: E402
    SegmentationError, assign_finger_positions, segment_hand,
)
from app.services.matcher import (  # noqa: E402
    MinutiaeMatcher, RIGHT_HAND_FINGERS, fuse_scores, get_matcher, match_hands,
)
from fastapi import HTTPException  # noqa: E402

_DATA = _ROOT.parent / "datasets/ridgebase/Task1/Test/Contactless"
_RB = re.compile(
    r"^\d+_(?P<dev>[A-Za-z0-9]+)_(?P<id>\d+)_(?P<seq>\d+)_(?P<hand>LEFT|RIGHT)_"
    r"image_fingerprint[A-Za-z0-9]+_(?P<finger>\d+)$", re.I)


def synthetic_right_hand() -> np.ndarray:
    img = np.full((480, 400, 3), 30, np.uint8)
    cv2.rectangle(img, (90, 300), (310, 460), (180, 160, 150), -1)
    for x, top in zip([110, 165, 220, 275], [140, 110, 120, 175]):
        cv2.rectangle(img, (x, top), (x + 35, 320), (180, 160, 150), -1)
    return img


def b64png(img: np.ndarray) -> str:
    return base64.b64encode(cv2.imencode(".png", img)[1]).decode()


def real_right_hands() -> dict:
    hands: dict = defaultdict(dict)
    for p in _DATA.glob("*.png"):
        m = _RB.match(p.stem)
        if m and m["hand"].upper() == "RIGHT":
            hands[(m["id"], m["dev"], m["seq"])][int(m["finger"])] = p
    return {k: v for k, v in hands.items() if len(v) == 4}


def test_fusion_helpers() -> None:
    assert fuse_scores([10, 20, 30], "mean") == 20, "mean fusion"
    assert fuse_scores([10, 20, 30], "max") == 30, "max fusion"
    assert fuse_scores([10, 20, 30], "min") == 10, "min fusion"
    assert fuse_scores([], "mean") == 0.0, "empty fusion -> 0"


def test_domain_routing() -> None:
    assert get_matcher("contact").name == "minutiae-crossing-number", "contact -> minutiae"
    # Contactless routes to the embedding matcher when its model is installed,
    # else falls back to minutiae. Assert the correct branch for this machine.
    from app.services.embedding_service import EmbeddingMatcher
    cl = get_matcher("contactless").name
    if EmbeddingMatcher.from_env().available:
        assert cl == "onnx-contactless-embedding", "contactless -> embedding (model present)"
    else:
        assert cl == "minutiae-crossing-number", "contactless -> minutiae fallback (no model)"


def test_segmentation() -> None:
    crops = segment_hand(synthetic_right_hand(), hand="right", want=4)
    assert len(crops) == 4, "4 finger crops located"
    assert [c.finger_position for c in crops] == list(RIGHT_HAND_FINGERS), \
        "crops named index..little (right hand)"
    assert assign_finger_positions(4, "left")[0] == "left_little", \
        "left hand: leftmost crop == little"
    with pytest.raises(SegmentationError):
        segment_hand(np.zeros((80, 80, 3), np.uint8), want=4)


def test_match_hands_guard() -> None:
    mt = MinutiaeMatcher()
    crops = segment_hand(synthetic_right_hand(), hand="right", want=4)
    hand = {c.finger_position: mt.extract(c.image) for c in crops}
    partial = {k: hand[k] for k in list(hand)[:2]}
    fused, _, _ = match_hands(partial, hand, matcher=mt, min_fingers=3)
    assert fused == 0.0, "2 shared fingers with min 3 -> 0.0 (no false accept)"


def test_endpoints_synthetic() -> None:
    resp = process_hand(ProcessHandRequest(image=b64png(synthetic_right_hand()),
                                            hand="right", domain="contactless"))
    assert [f.finger_position for f in resp.fingers] == list(RIGHT_HAND_FINGERS), \
        "process-hand returns 4 named fingers"
    probe = {f.finger_position: f.template for f in resp.fingers}
    with pytest.raises(HTTPException) as exc:
        match_hand(MatchHandRequest(probe=probe, candidates=[]))
    assert exc.value.status_code == 400, "empty candidates -> 400"
    with pytest.raises(HTTPException) as exc:
        process_hand(ProcessHandRequest(image=b64png(np.zeros((80, 80, 3), np.uint8)), hand="right"))
    assert exc.value.status_code == 422, "blank image -> 422"


def test_real_selfmatch() -> None:
    full = real_right_hands()
    if not full:
        pytest.skip("RidgeBase dataset not present")
    mt = MinutiaeMatcher()
    fm = full[list(full)[0]]
    hand = {RIGHT_HAND_FINGERS[i]: mt.extract(cv2.imread(str(p)), enhance=True)
            for i, p in fm.items()}
    # Minutiae templates -> verify on the contact path (embedding path would be
    # a format mismatch). Validates fusion/scoring, not the contactless matcher.
    m = match_hand(MatchHandRequest(
        probe=hand, candidates=[CandidateHand(patient_id=1, fingers=hand)],
        domain="contact"))
    assert m.score > 99, f"self-match on real ridges ~100 (got {m.score})"


def test_embedding_path() -> None:
    from app.services.embedding_service import EmbeddingMatcher
    em = EmbeddingMatcher.from_env()
    if not em.available:
        pytest.skip("no ONNX model available")
    full = real_right_hands()
    if not full:
        pytest.skip("RidgeBase dataset not present")
    p = next(iter(full.values()))[0]
    img = cv2.imread(str(p))
    t1 = em.extract(img, hand="right")
    assert t1["format"] == "embedding" and t1["dim"] == 1024, "embedding is 1024-d"
    # Same image twice -> cosine 1.0 -> score ~100.
    assert em.score(t1, em.extract(img, hand="right")) > 99.9, "embedding self-match ~100"
