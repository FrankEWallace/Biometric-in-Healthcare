#!/usr/bin/env python3
"""
Validate the ONNX embedding matcher end-to-end through the SERVICE path.

Embeds RidgeBase Task1 Test/Contactless crops with the production
EmbeddingMatcher (ONNX + our preprocessing), then computes CL2CL genuine/impostor
scores, EER, and a suggested accept threshold. This is the "run the dataset
through our own pipeline" check — it should reproduce the ~8% CL2CL EER measured
with the reference torch model, confirming the ONNX export + preprocessing are
faithful, and it produces the number to set as
services.fingerprint.contactless_match_threshold.

    EMBEDDING_MODEL_PATH=models/contactless_embedding.onnx \
        venv/bin/python tools/validate_embedding_ridgebase.py [--limit N]
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
_RE = re.compile(
    r"^\d+_[A-Za-z0-9]+_(?P<id>\d+)_\d+_(?P<hand>LEFT|RIGHT)_image_"
    r"fingerprint[A-Za-z0-9]+_(?P<finger>\d+)$", re.I)


def eer(genuine: list[float], impostor: list[float]) -> tuple[float, float]:
    """Return (EER%, threshold) by sweeping the pooled score range."""
    scores = sorted(set(genuine + impostor))
    g = np.array(genuine); im = np.array(impostor)
    best = (1e9, 0.0)
    for t in scores:
        frr = float(np.mean(g < t))          # genuine rejected
        far = float(np.mean(im >= t))         # impostor accepted
        if abs(frr - far) < best[0]:
            best = (abs(frr - far), t)
    t = best[1]
    return (float((np.mean(g < t) + np.mean(im >= t)) / 2 * 100), t)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="cap images (0 = all)")
    ap.add_argument("--impostors", type=int, default=20000)
    args = ap.parse_args()
    random.seed(42)

    matcher = EmbeddingMatcher.from_env()
    if not matcher.available:
        sys.exit(f"No model at {matcher.model_path} — set EMBEDDING_MODEL_PATH.")

    paths = sorted(_DATA.glob("*.png"))
    if args.limit:
        paths = paths[: args.limit]

    # Embed each crop; key identity on (id, hand, finger) like the harness.
    by_identity: dict[str, list[np.ndarray]] = defaultdict(list)
    print(f"Embedding {len(paths)} crops via {matcher.name} ...")
    for i, p in enumerate(paths, 1):
        m = _RE.match(p.stem)
        if not m:
            continue
        img = cv2.imread(str(p))
        if img is None:
            continue
        tmpl = matcher.extract(img, hand=m["hand"])
        vec = np.asarray(tmpl["vector"], dtype=np.float32)
        ident = f"{m['id']}_{m['hand'].upper()}_{m['finger']}"
        by_identity[ident].append(vec)
        if i % 200 == 0:
            print(f"  [{i}/{len(paths)}]")

    vecs = {k: v for k, v in by_identity.items() if len(v) >= 2}
    print(f"{len(vecs)} identities with ≥2 impressions")

    def cos100(a, b):  # matches EmbeddingMatcher.score mapping
        return max(0.0, float(np.dot(a, b))) * 100.0

    genuine: list[float] = []
    for vs in vecs.values():
        for a, b in itertools.combinations(vs, 2):
            genuine.append(cos100(a, b))

    idents = list(vecs)
    impostor: list[float] = []
    while len(impostor) < args.impostors:
        i, j = random.sample(idents, 2)
        a = random.choice(vecs[i]); b = random.choice(vecs[j])
        impostor.append(cos100(a, b))

    e, thr = eer(genuine, impostor)
    g = np.array(genuine); im = np.array(impostor)
    # threshold at FAR≈1%
    far1 = float(np.quantile(im, 0.99))
    frr_at_far1 = float(np.mean(g < far1))
    print("\n" + "=" * 56)
    print(f"CL2CL via service EmbeddingMatcher (ONNX)")
    print(f"  genuine pairs  : {len(genuine)}  mean {g.mean():.1f}  sd {g.std():.1f}")
    print(f"  impostor pairs : {len(impostor)}  mean {im.mean():.1f}  sd {im.std():.1f}")
    print(f"  EER            : {e:.2f}%  at threshold {thr:.2f}")
    print(f"  FAR~1% thresh  : {far1:.2f}  (FRR {frr_at_far1*100:.1f}%)")
    print("=" * 56)
    print("Reference (torch): CL2CL EER 8.13%. Set contactless threshold from EER/FAR above.")


if __name__ == "__main__":
    main()
