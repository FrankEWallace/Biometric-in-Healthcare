#!/usr/bin/env python3
"""
Four-finger fused calibration of the ONNX embedding matcher on RidgeBase.

Mirrors ridgebase_eval.py's four-finger mode (same hand-sample grouping, mean
fusion, ≥3 shared fingers) but scores with the production EmbeddingMatcher — so
the threshold it derives is on the *fused hand score verify-hand actually uses*.
Compare against the minutiae four-finger runs (EER ~42-47%).

Embeddings are cached to an .npz (keyed by filename) so re-runs are instant.

    EMBEDDING_MODEL_PATH=models/contactless_embedding.onnx \
        venv/bin/python tools/validate_embedding_fourfinger.py [--min-fingers 3]
"""
from __future__ import annotations

import argparse
import itertools
import random
import re
import sys
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from app.services.embedding_service import EmbeddingMatcher  # noqa: E402

_DATA = _ROOT.parent / "datasets/ridgebase/Task1/Test/Contactless"
_CACHE = _ROOT / "tools" / ".rb_test_embeddings.npz"

# Same contactless crop grammar as ridgebase_eval.py.
_RB = re.compile(
    r"^(?P<session>\d+)_(?P<device>[A-Za-z0-9]+)_(?P<identity>\d+)_(?P<bg>\d+)_"
    r"(?P<hand>LEFT|RIGHT)_image_fingerprint(?P<seq>[A-Za-z0-9]+)"
    r"(?:_(?P<conf>[0-9.]+))?_(?P<finger>\d+)$", re.I)


def eer(genuine: list[float], impostor: list[float]) -> tuple[float, float]:
    g, im = np.array(genuine), np.array(impostor)
    best = (1e9, 0.0)
    for t in sorted(set(genuine + impostor)):
        diff = abs(np.mean(g < t) - np.mean(im >= t))
        if diff < best[0]:
            best = (diff, t)
    t = best[1]
    return (float((np.mean(g < t) + np.mean(im >= t)) / 2 * 100), t)


def load_embeddings(matcher: EmbeddingMatcher) -> dict[str, np.ndarray]:
    """Embed every crop once (with hand orientation); cache to .npz."""
    if _CACHE.exists():
        data = np.load(_CACHE)
        print(f"loaded {len(data.files)} cached embeddings from {_CACHE.name}")
        return {k: data[k] for k in data.files}

    paths = sorted(_DATA.glob("*.png"))
    out: dict[str, np.ndarray] = {}
    print(f"embedding {len(paths)} crops (one-time, ~30 min CPU)...")
    for i, p in enumerate(paths, 1):
        m = _RB.match(p.stem)
        if not m:
            continue
        img = cv2.imread(str(p))
        if img is None:
            continue
        out[p.name] = np.asarray(matcher.extract(img, hand=m["hand"])["vector"], dtype=np.float32)
        if i % 200 == 0:
            print(f"  [{i}/{len(paths)}]")
    np.savez(_CACHE, **out)
    print(f"cached {len(out)} embeddings -> {_CACHE.name}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-fingers", type=int, default=3)
    ap.add_argument("--max-impostor", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    matcher = EmbeddingMatcher.from_env()
    if not matcher.available and not _CACHE.exists():
        sys.exit(f"No model at {matcher.model_path} — set EMBEDDING_MODEL_PATH.")
    emb = load_embeddings(matcher)

    # Group crops into hand-samples: (identity,hand,device,bg,seq) -> {finger: name}
    samples: dict[tuple, dict[str, str]] = defaultdict(dict)
    for name in emb:
        m = _RB.match(Path(name).stem)
        key = (m["identity"], m["hand"].upper(), m["device"], m["bg"], m["seq"])
        samples[key][m["finger"]] = name

    hands: dict[tuple, list[dict[str, str]]] = defaultdict(list)
    for (ident, hand, _d, _b, _s), fingers in samples.items():
        hands[(ident, hand)].append(fingers)
    hands = {k: v for k, v in hands.items() if len(v) >= 2}
    print(f"Grouped {len(samples)} hand-samples into {len(hands)} hand-identities (>=2 samples).")

    def fuse(sa: dict[str, str], sb: dict[str, str]) -> float | None:
        shared = sorted(set(sa) & set(sb))
        if len(shared) < args.min_fingers:
            return None
        scores = []
        for fg in shared:
            a, b = emb[sa[fg]], emb[sb[fg]]
            scores.append(max(0.0, float(np.dot(a, b))) * 100.0)  # cosine->0-100
        if len(scores) < args.min_fingers:
            return None
        return sum(scores) / len(scores)

    hand_ids = list(hands)
    rng = random.Random(args.seed)
    genuine, impostor = [], []
    for hid in hand_ids:
        for sa, sb in itertools.combinations(hands[hid], 2):
            s = fuse(sa, sb)
            if s is not None:
                genuine.append(s)
    cross = [(a, b) for a in hand_ids for b in hand_ids if a < b]
    rng.shuffle(cross)
    for a, b in cross:
        if len(impostor) >= args.max_impostor:
            break
        s = fuse(rng.choice(hands[a]), rng.choice(hands[b]))
        if s is not None:
            impostor.append(s)

    e, thr = eer(genuine, impostor)
    g, im = np.array(genuine), np.array(impostor)
    far1 = float(np.quantile(im, 0.99))
    frr_at_far1 = float(np.mean(g < far1))
    print("\n" + "=" * 60)
    print("FOUR-FINGER FUSED — ONNX embedding matcher (RidgeBase Test)")
    print(f"  hand-identities : {len(hands)}   min shared fingers {args.min_fingers}")
    print(f"  genuine pairs   : {len(genuine)}  mean {g.mean():.1f}  sd {g.std():.1f}")
    print(f"  impostor pairs  : {len(impostor)}  mean {im.mean():.1f}  sd {im.std():.1f}")
    print(f"  EER             : {e:.2f}%  at fused threshold {thr:.2f}")
    print(f"  FAR~1% thresh   : {far1:.2f}  (FRR {frr_at_far1*100:.1f}%)")
    print("=" * 60)
    print("cf. single-finger CL2CL EER 8.05%; minutiae four-finger EER ~42-47%.")


if __name__ == "__main__":
    main()
