#!/usr/bin/env python3
"""
Four-finger pipeline tests: matcher interface, fusion, segmentation, endpoints.

Runnable without pytest and without the (gitignored) RidgeBase dataset — the
dataset-dependent checks (self-match == 100 on real ridges) are skipped with a
notice when the data isn't present, so this passes in CI too.

    python tests/test_four_finger.py
"""
from __future__ import annotations

import base64
import re
import sys
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

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

_passed = 0


def check(cond: bool, msg: str) -> None:
    global _passed
    if not cond:
        raise AssertionError(msg)
    _passed += 1
    print(f"  ✓ {msg}")


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
    print("fusion helpers")
    check(fuse_scores([10, 20, 30], "mean") == 20, "mean fusion")
    check(fuse_scores([10, 20, 30], "max") == 30, "max fusion")
    check(fuse_scores([10, 20, 30], "min") == 10, "min fusion")
    check(fuse_scores([], "mean") == 0.0, "empty fusion -> 0")


def test_domain_routing() -> None:
    print("domain routing")
    check(get_matcher("contact").name == "minutiae-crossing-number", "contact -> minutiae")
    # No embedding model installed -> contactless falls back to minutiae.
    check(get_matcher("contactless").name == "minutiae-crossing-number",
          "contactless -> minutiae fallback (no model)")


def test_segmentation() -> None:
    print("segmentation")
    crops = segment_hand(synthetic_right_hand(), hand="right", want=4)
    check(len(crops) == 4, "4 finger crops located")
    check([c.finger_position for c in crops] == list(RIGHT_HAND_FINGERS),
          "crops named index..little (right hand)")
    check(assign_finger_positions(4, "left")[0] == "left_little",
          "left hand: leftmost crop == little")
    try:
        segment_hand(np.zeros((80, 80, 3), np.uint8), want=4)
        check(False, "blank frame should raise")
    except SegmentationError:
        check(True, "blank frame rejected")


def test_match_hands_guard() -> None:
    print("match_hands min-fingers guard")
    mt = MinutiaeMatcher()
    crops = segment_hand(synthetic_right_hand(), hand="right", want=4)
    hand = {c.finger_position: mt.extract(c.image) for c in crops}
    partial = {k: hand[k] for k in list(hand)[:2]}
    fused, _, _ = match_hands(partial, hand, matcher=mt, min_fingers=3)
    check(fused == 0.0, "2 shared fingers with min 3 -> 0.0 (no false accept)")


def test_endpoints_synthetic() -> None:
    print("endpoints (synthetic hand)")
    resp = process_hand(ProcessHandRequest(image=b64png(synthetic_right_hand()),
                                            hand="right", domain="contactless"))
    check([f.finger_position for f in resp.fingers] == list(RIGHT_HAND_FINGERS),
          "process-hand returns 4 named fingers")
    probe = {f.finger_position: f.template for f in resp.fingers}
    try:
        match_hand(MatchHandRequest(probe=probe, candidates=[]))
        check(False, "empty candidates should 400")
    except HTTPException as e:
        check(e.status_code == 400, "empty candidates -> 400")
    try:
        process_hand(ProcessHandRequest(image=b64png(np.zeros((80, 80, 3), np.uint8)), hand="right"))
        check(False, "blank image should 422")
    except HTTPException as e:
        check(e.status_code == 422, "blank image -> 422")


def test_real_selfmatch() -> None:
    print("real-crop self-match (needs RidgeBase)")
    full = real_right_hands()
    if not full:
        print("  ⚠ RidgeBase not present — skipping self-match value check")
        return
    mt = MinutiaeMatcher()
    fm = full[list(full)[0]]
    hand = {RIGHT_HAND_FINGERS[i]: mt.extract(cv2.imread(str(p)), enhance=True)
            for i, p in fm.items()}
    m = match_hand(MatchHandRequest(
        probe=hand, candidates=[CandidateHand(patient_id=1, fingers=hand)],
        domain="contactless"))
    check(m.score > 99, f"self-match on real ridges ~100 (got {m.score})")


if __name__ == "__main__":
    for t in (test_fusion_helpers, test_domain_routing, test_segmentation,
              test_match_hands_guard, test_endpoints_synthetic, test_real_selfmatch):
        t()
    print(f"\n{_passed} checks passed.")
