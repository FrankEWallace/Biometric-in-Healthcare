#!/usr/bin/env python3
"""
RidgeBase multi-scenario evaluation harness.

The base tool (`calibrate_far_frr.py`) does *within-set* single-finger matching
(one pool, genuine = same identity, impostor = different). RidgeBase needs three
things it can't express, so this tool adds them while reusing the same production
template-extraction + metric core:

  1. cross-domain gallery/probe matching driven by the official Task3 protocol
     JSONs  -> C2CL (contact enrolled, contactless probe) and CL2CL set splits.
  2. four-finger fusion  -> fuse the 4 single-finger scores of a hand into one
     match score (NISTIR 8307: 4-finger slap is far more accurate than 1 finger).
  3. rank-1 identification (closed-set) alongside verification FAR/FRR.

Modes
-----
  protocol   --protocol <task3.json> --split test [--scenario c2cl|cl2cl]
             Genuine = probe image vs gallery image of the SAME finger-identity;
             impostor = probe vs gallery of OTHER identities (sampled).
             The JSON encodes the contact finger-name <-> contactless finger-index
             mapping, so it is the authoritative source for C2CL pairing.

  four-finger --data <Task1/<split>/Contactless>
             Group single-finger crops into hand-samples (one photo -> up to 4
             finger crops), fuse per-finger scores, and score hand vs hand.

Both modes reuse compute_metrics / write_outputs / print_summary and emit the
same artefacts (scores.csv, roc.csv, calibration_report.json, plots).

Usage
-----
  python tools/ridgebase_eval.py protocol \
    --protocol ../datasets/ridgebase/Task3/DistalMatching/set_based_test_c2cl.json \
    --images-root ../datasets/ridgebase/Task1/Test \
    --out ../docs/calibration/ridgebase/c2cl_test [--no-enhance]

  python tools/ridgebase_eval.py four-finger \
    --data ../datasets/ridgebase/Task1/Test/Contactless \
    --out ../docs/calibration/ridgebase/fourfinger_test [--no-enhance]
"""

from __future__ import annotations

import argparse
import itertools
import json
import random
import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

# Reuse the production pipeline + metric core from the base harness.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from calibrate_far_frr import (  # noqa: E402
    PairScore,
    compute_metrics,
    image_to_template,
    print_summary,
    write_outputs,
    _IMAGE_EXTS,
)


# ===========================================================================
# Filename parsing
# ===========================================================================

# Contactless single-finger crop:
#   <session>_<device>_<identity>_<bg>_<hand>_image_fingerprint<seq>[_<conf>]_<finger>.png
_RB_CONTACTLESS = re.compile(
    r"^(?P<session>\d+)_(?P<device>[A-Za-z0-9]+)_(?P<identity>\d+)_(?P<bg>\d+)_"
    r"(?P<hand>LEFT|RIGHT)_image_fingerprint(?P<seq>[A-Za-z0-9]+)"
    r"(?:_(?P<conf>[0-9.]+))?_(?P<finger>\d+)$",
    re.IGNORECASE,
)


def parse_contactless(stem: str) -> dict | None:
    m = _RB_CONTACTLESS.match(stem)
    return m.groupdict() if m else None


# ===========================================================================
# Template cache — extract once per physical image, reuse across pairs
# ===========================================================================

class TemplateCache:
    def __init__(self, enhance: bool):
        self.enhance = enhance
        self._cache: dict[Path, dict | None] = {}
        self.dropped = 0

    def get(self, path: Path) -> dict | None:
        if path not in self._cache:
            self._cache[path] = self._build(path)
        return self._cache[path]

    def _build(self, path: Path) -> dict | None:
        try:
            template, _ = image_to_template(path, enhance=self.enhance)
        except Exception as exc:  # noqa: BLE001
            print(f"  ! skip {path.name}: {exc}", file=sys.stderr)
            self.dropped += 1
            return None
        if template.get("status") == "no_features" or template.get("minutiae_count", 0) == 0:
            print(f"  ! drop {path.name}: no usable minutiae", file=sys.stderr)
            self.dropped += 1
            return None
        return template


def build_file_index(images_root: Path) -> dict[str, Path]:
    """Map every image basename under images_root to its full path (for protocol lookup)."""
    index: dict[str, Path] = {}
    for path in images_root.rglob("*"):
        if path.is_file() and path.suffix.lower() in _IMAGE_EXTS:
            index[path.name] = path
    return index


# ===========================================================================
# Mode: protocol-driven gallery/probe (C2CL / CL2CL)
# ===========================================================================

def run_protocol(args) -> int:
    from app.services.sourceafis_service import match_templates

    protocol = json.loads(Path(args.protocol).read_text())
    index = build_file_index(Path(args.images_root))
    print(f"Loaded protocol with {len(protocol)} finger-identities; "
          f"indexed {len(index)} images under {args.images_root}")

    enhance = not args.no_enhance
    cache = TemplateCache(enhance)

    # Resolve each identity's gallery/query file paths (skip any missing on disk).
    entries: dict[str, dict[str, list[Path]]] = {}
    missing = 0
    for ident, sets in protocol.items():
        g, q = [], []
        for role, dst in (("gallery", g), (args.query_key, q)):
            for name in sets.get(role, []):
                p = index.get(name)
                if p is None:
                    missing += 1
                else:
                    dst.append(p)
        if g and q:
            entries[ident] = {"gallery": g, "query": q}
    if missing:
        print(f"  ({missing} referenced files not found under images-root — skipped)",
              file=sys.stderr)
    print(f"Usable identities: {len(entries)}")
    if len(entries) < 2:
        print("ERROR: need >=2 identities with both gallery and query present", file=sys.stderr)
        return 1

    # Pre-extract every referenced template once.
    all_paths = {p for e in entries.values() for role in ("gallery", "query") for p in e[role]}
    print(f"Extracting {len(all_paths)} templates ({'enhance' if enhance else 'no-enhance'}) ...")
    for i, p in enumerate(sorted(all_paths), 1):
        cache.get(p)
        if i % 200 == 0:
            print(f"  [{i}/{len(all_paths)}]")

    def tmpls(paths):
        out = [(p, cache.get(p)) for p in paths]
        return [(p, t) for p, t in out if t is not None]

    ids = list(entries)
    rng = random.Random(args.seed)

    # --- genuine: query x gallery within the same finger-identity ---
    pairs: list[PairScore] = []
    for ident in ids:
        gs = tmpls(entries[ident]["gallery"])
        qs = tmpls(entries[ident]["query"])
        for (qp, qt) in qs:
            for (gp, gt) in gs:
                pairs.append(PairScore(qp.name, gp.name, "genuine",
                                       float(match_templates(qt, gt))))

    # --- impostor: query of one identity x gallery of others (sampled) ---
    impostor_budget = args.max_impostor
    cross: list[tuple[str, str]] = [(a, b) for a in ids for b in ids if a != b]
    rng.shuffle(cross)
    added = 0
    for a, b in cross:
        if impostor_budget and added >= impostor_budget:
            break
        qs = tmpls(entries[a]["query"])
        gs = tmpls(entries[b]["gallery"])
        if not qs or not gs:
            continue
        qp, qt = rng.choice(qs)
        gp, gt = rng.choice(gs)
        pairs.append(PairScore(qp.name, gp.name, "impostor",
                               float(match_templates(qt, gt))))
        added += 1

    # --- rank-1 identification (closed set): each query set's best gallery match ---
    rank1 = _rank1_identification(entries, cache, match_templates)

    _finish(args, pairs, enhance, extra={
        "mode": "protocol",
        "scenario": args.scenario,
        "protocol": str(args.protocol),
        "identities": len(entries),
        "templates_dropped": cache.dropped,
        "rank1_accuracy": rank1,
    })
    print(f"\nRank-1 identification accuracy: {rank1*100:.1f}%")
    return 0


def _rank1_identification(entries, cache, match_templates) -> float:
    """Closed-set: for each query image, does its top-scoring gallery identity match?"""
    gallery_tmpls = {
        ident: [(p, cache.get(p)) for p in e["gallery"] if cache.get(p) is not None]
        for ident, e in entries.items()
    }
    correct = total = 0
    for ident, e in entries.items():
        for qp in e["query"]:
            qt = cache.get(qp)
            if qt is None:
                continue
            best_ident, best_score = None, -1.0
            for gid, gts in gallery_tmpls.items():
                for _, gt in gts:
                    s = float(match_templates(qt, gt))
                    if s > best_score:
                        best_score, best_ident = s, gid
            total += 1
            if best_ident == ident:
                correct += 1
    return correct / total if total else 0.0


# ===========================================================================
# Mode: four-finger fusion (CL2CL)
# ===========================================================================

def run_four_finger(args) -> int:
    from app.services.sourceafis_service import match_templates

    data = Path(args.data)
    enhance = not args.no_enhance
    cache = TemplateCache(enhance)

    # Group crops into hand-samples: (identity, hand, device, bg, seq) -> {finger: path}
    samples: dict[tuple, dict[str, Path]] = {}
    for path in sorted(data.rglob("*")):
        if not (path.is_file() and path.suffix.lower() in _IMAGE_EXTS):
            continue
        f = parse_contactless(path.stem)
        if not f:
            continue
        key = (f["identity"], f["hand"].upper(), f["device"], f["bg"], f["seq"])
        samples.setdefault(key, {})[f["finger"]] = path

    # A hand-identity is (identity, hand); its samples are the distinct photos of it.
    hands: dict[tuple, list[dict[str, Path]]] = {}
    for (ident, hand, _dev, _bg, _seq), fingers in samples.items():
        hands.setdefault((ident, hand), []).append(fingers)
    hands = {k: v for k, v in hands.items() if len(v) >= 2}
    print(f"Grouped {len(samples)} hand-samples into {len(hands)} hand-identities "
          f"with >=2 samples (min {args.min_fingers} shared fingers per pair).")
    if len(hands) < 2:
        print("ERROR: need >=2 hand-identities with >=2 samples each", file=sys.stderr)
        return 1

    def fuse(sa: dict[str, Path], sb: dict[str, Path]) -> float | None:
        shared = sorted(set(sa) & set(sb))
        if len(shared) < args.min_fingers:
            return None
        scores = []
        for fg in shared:
            ta, tb = cache.get(sa[fg]), cache.get(sb[fg])
            if ta is None or tb is None:
                continue
            scores.append(float(match_templates(ta, tb)))
        if len(scores) < args.min_fingers:
            return None
        return sum(scores) / len(scores)  # mean fusion

    hand_ids = list(hands)
    rng = random.Random(args.seed)
    pairs: list[PairScore] = []

    # genuine: sample pairs within the same hand-identity
    for hid in hand_ids:
        for sa, sb in itertools.combinations(hands[hid], 2):
            s = fuse(sa, sb)
            if s is not None:
                pairs.append(PairScore(f"{hid}", f"{hid}", "genuine", s))

    # impostor: hand-sample of one identity vs another (sampled)
    cross = [(a, b) for a in hand_ids for b in hand_ids if a < b]
    rng.shuffle(cross)
    added = 0
    for a, b in cross:
        if args.max_impostor and added >= args.max_impostor:
            break
        s = fuse(rng.choice(hands[a]), rng.choice(hands[b]))
        if s is not None:
            pairs.append(PairScore(f"{a}", f"{b}", "impostor", s))
            added += 1

    _finish(args, pairs, enhance, extra={
        "mode": "four-finger",
        "data": str(data),
        "hand_identities": len(hands),
        "min_fingers": args.min_fingers,
        "templates_dropped": cache.dropped,
    })
    return 0


# ===========================================================================
# Shared finish: metrics + outputs
# ===========================================================================

def _finish(args, pairs: list[PairScore], enhance: bool, extra: dict) -> None:
    genuine = [p.score for p in pairs if p.label == "genuine"]
    impostor = [p.score for p in pairs if p.label == "impostor"]
    print(f"\nScored {len(genuine)} genuine + {len(impostor)} impostor pairs.")
    if not genuine or not impostor:
        print("ERROR: need at least one genuine and one impostor pair", file=sys.stderr)
        raise SystemExit(1)

    m = compute_metrics(genuine, impostor, args.step, args.far_targets)
    print_summary(m)
    meta = {
        "seed": args.seed, "step": args.step, "far_targets": args.far_targets,
        "enhance": enhance, "max_impostor": args.max_impostor, **extra,
    }
    write_outputs(args.out, pairs, m, meta)


# ===========================================================================
# CLI
# ===========================================================================

def main() -> int:
    ap = argparse.ArgumentParser(description="RidgeBase multi-scenario evaluation")
    sub = ap.add_subparsers(dest="mode", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--out", type=Path, required=True)
    common.add_argument("--no-enhance", action="store_true")
    common.add_argument("--seed", type=int, default=42)
    common.add_argument("--step", type=float, default=0.5)
    common.add_argument("--max-impostor", type=int, default=20000)
    common.add_argument("--far-targets", type=float, nargs="+", default=[0.01, 0.001])

    p_proto = sub.add_parser("protocol", parents=[common],
                             help="Task3 gallery/probe protocol (C2CL / CL2CL)")
    p_proto.add_argument("--protocol", type=Path, required=True)
    p_proto.add_argument("--images-root", type=Path, required=True,
                         help="Task1/<split> root holding Contactless/ and Contactbased/")
    p_proto.add_argument("--scenario", choices=["c2cl", "cl2cl"], default="c2cl")
    p_proto.add_argument("--query-key", default="query",
                         help="JSON key holding probe filenames (default: query)")

    p_ff = sub.add_parser("four-finger", parents=[common],
                          help="Four-finger fusion on contactless single-finger crops")
    p_ff.add_argument("--data", type=Path, required=True)
    p_ff.add_argument("--min-fingers", type=int, default=3,
                      help="Min shared fingers required to fuse a pair (default 3)")

    args = ap.parse_args()
    if args.mode == "protocol":
        return run_protocol(args)
    if args.mode == "four-finger":
        return run_four_finger(args)
    ap.error(f"unknown mode {args.mode}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
