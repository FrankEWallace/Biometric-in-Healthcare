"""Always-on unit tests for score fusion (app/services/matcher.py:fuse_scores)."""
from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from app.services.matcher import fuse_scores  # noqa: E402


def test_fuse_scores_happy_path_four_fingers() -> None:
    scores = [80.0, 90.0, 70.0, 100.0]
    assert fuse_scores(scores, "mean") == sum(scores) / 4
    assert fuse_scores(scores, "max") == 100.0
    assert fuse_scores(scores, "min") == 70.0


def test_fuse_scores_fewer_than_four_fingers() -> None:
    for scores in ([80.0, 90.0], [80.0, 90.0, 70.0]):
        fused = fuse_scores(scores, "mean")
        assert fused == sum(scores) / len(scores)
        assert fused == fused  # not NaN — no division-by-zero


def test_fuse_scores_empty_input_returns_zero() -> None:
    assert fuse_scores([], "mean") == 0.0
    assert fuse_scores([], "max") == 0.0
    assert fuse_scores([], "min") == 0.0


def test_fuse_scores_ordering_invariant() -> None:
    high = fuse_scores([90.0, 90.0, 90.0, 90.0], "mean")
    low = fuse_scores([40.0, 40.0, 40.0, 40.0], "mean")
    assert high > low, "higher per-finger scores must never fuse to a lower score"

    # Mixed input should fall between the min and max of its own scores —
    # fusion should never invent a score outside the range it was given.
    mixed = fuse_scores([40.0, 90.0], "mean")
    assert 40.0 <= mixed <= 90.0
