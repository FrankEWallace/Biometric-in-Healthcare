#!/usr/bin/env python3
"""
FAR / FRR calibration harness for the fingerprint matcher.

Runs the *production* pipeline (preprocess_fingerprint -> extract_template ->
match_templates) over a labelled set of fingerprint captures, builds the
genuine and impostor score distributions, and reports the operating
characteristics needed to pick a defensible MATCH_THRESHOLD:

  - FAR(t)  false accept rate  = P(impostor score >= t)
  - FRR(t)  false reject rate  = P(genuine  score <  t)
  - EER     equal error rate   (threshold where FAR == FRR)
  - threshold at target FAR (e.g. 1%, 0.1%) and the FRR you pay for it

Because it imports the real services, the numbers it produces are the numbers
production will see — change the algorithm and re-run to recalibrate.

--------------------------------------------------------------------------
Dataset layout
--------------------------------------------------------------------------
Every image belongs to one *identity* (a single physical finger). Multiple
impressions/captures of that finger share the identity. Identity is derived
from the path:

  data/
    subject01/
      right_index_1.jpg   ┐ identity = "subject01/right_index"
      right_index_2.jpg   ┘
      right_thumb_1.jpg     identity = "subject01/right_thumb"
    subject02/
      right_index_1.jpg     identity = "subject02/right_index"

A flat FVC-style layout also works: "101_1.tif", "101_2.tif", "102_1.tif"
-> identities "101", "102" (the trailing _<sample> token is stripped).

  - genuine  pair = two impressions of the SAME identity
  - impostor pair = two impressions of DIFFERENT identities

--------------------------------------------------------------------------
Usage
--------------------------------------------------------------------------
  python tools/calibrate_far_frr.py --data /path/to/captures --out reports/
  python tools/calibrate_far_frr.py --self-test     # verify the metric math

Outputs (written to --out, default ./calibration_out):
  scores.csv              every pair with its label and score
  roc.csv                 threshold, far, frr across the grid
  calibration_report.json machine-readable summary
  far_frr.png / roc.png   plots (only if matplotlib is installed)
"""

from __future__ import annotations

import argparse
import base64
import itertools
import json
import os
import random
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

# Allow running from anywhere: add the python-service root (parent of tools/)
_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}


# ===========================================================================
# Identity resolution
# ===========================================================================

def _strip_sample_suffix(stem: str) -> str:
    """
    Strip a trailing capture/sample index from a filename stem.

    "right_index_2" -> "right_index"   "101-3" -> "101"   "thumb" -> "thumb"
    Only a final token that is purely digits is removed, so finger names that
    happen to end in a word are preserved.
    """
    for sep in ("_", "-"):
        head, _, tail = stem.rpartition(sep)
        if head and tail.isdigit():
            return head
    return stem


def identity_for(path: Path, root: Path) -> str | None:
    """Identity key = relative directory path + finger label (sample idx stripped)."""
    rel = path.relative_to(root)
    finger = _strip_sample_suffix(path.stem)
    parts = list(rel.parts[:-1]) + [finger]
    return "/".join(parts)


# RidgeBase Task1 Contactless filenames:
#   <session>_<device>_<identity>_<background>_<hand>_image_fingerprint<seq>[_<confidence>]_<finger>.png
# e.g. "1_Apple_10727_1_LEFT_image_fingerprint8GIFPDNU_0.8888496_3.png" (Train, has confidence)
#      "1_Apple_14493_1_LEFT_image_fingerprintSMEG5K05_0.png"          (Test, no confidence)
# The same physical finger recurs across sessions/devices/backgrounds — those are the
# "impressions" we want grouped for genuine pairs, so identity = (identity, hand, finger),
# discarding session/device/background/seq/confidence.
_RIDGEBASE_CONTACTLESS_RE = re.compile(
    r"^\d+_[A-Za-z0-9]+_(?P<identity>\d+)_\d+_(?P<hand>LEFT|RIGHT)_image_fingerprint"
    r"[A-Za-z0-9]+(?:_[0-9.]+)?_(?P<finger>\d+)$",
    re.IGNORECASE,
)


def ridgebase_contactless_identity_for(path: Path, root: Path) -> str | None:
    """Identity key for RidgeBase Contactless captures; None for non-matching files (skipped)."""
    m = _RIDGEBASE_CONTACTLESS_RE.match(path.stem)
    if not m:
        return None
    return f"{m['identity']}_{m['hand'].upper()}_{m['finger']}"


IDENTITY_SCHEMES = {
    "generic": identity_for,
    "ridgebase-contactless": ridgebase_contactless_identity_for,
}


def discover_images(root: Path, identity_fn=identity_for) -> dict[str, list[Path]]:
    """Walk `root` and group image files by identity. Returns {identity: [paths]}."""
    groups: dict[str, list[Path]] = {}
    skipped = 0
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in _IMAGE_EXTS:
            key = identity_fn(path, root)
            if key is None:
                skipped += 1
                continue
            groups.setdefault(key, []).append(path)
    if skipped:
        print(f"  (skipped {skipped} files that didn't match the identity pattern)", file=sys.stderr)
    return groups


# ===========================================================================
# Template extraction — production pipeline
# ===========================================================================

def image_to_template(path: Path, enhance: bool = True) -> tuple[dict, float]:
    """Decode an image and run the same pipeline the /process endpoint uses."""
    import cv2  # imported lazily so --self-test works without OpenCV/numpy stack
    import numpy as np
    from app.services.image_processor import preprocess_fingerprint
    from app.services.sourceafis_service import extract_template

    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"could not decode image: {path}")

    result = preprocess_fingerprint(img, enhance=enhance)
    skeleton_bytes = base64.b64decode(result["processed_image"])
    skeleton = cv2.imdecode(np.frombuffer(skeleton_bytes, np.uint8), cv2.IMREAD_GRAYSCALE)
    if skeleton is None:
        raise ValueError(f"preprocessing produced an unreadable skeleton: {path}")

    template = extract_template(skeleton)
    return template, float(result.get("quality_score", 0.0))


def build_templates(groups: dict[str, list[Path]], enhance: bool = True) -> tuple[dict[str, list[tuple[Path, dict]]], int]:
    """
    Extract a template for every image. Drops images whose template has no
    usable features. Returns ({identity: [(path, template)]}, dropped_count).
    """
    out: dict[str, list[tuple[Path, dict]]] = {}
    total = sum(len(v) for v in groups.values())
    done = 0
    dropped = 0

    for identity, paths in groups.items():
        for path in paths:
            done += 1
            try:
                template, _ = image_to_template(path, enhance=enhance)
            except Exception as exc:  # noqa: BLE001 - report and skip bad files
                print(f"  ! skip {path.name}: {exc}", file=sys.stderr)
                dropped += 1
                continue

            if template.get("status") == "no_features" or template.get("minutiae_count", 0) == 0:
                print(f"  ! drop {path.name}: no usable minutiae", file=sys.stderr)
                dropped += 1
                continue

            out.setdefault(identity, []).append((path, template))
            print(f"  [{done}/{total}] {identity}  <-  {path.name}"
                  f"  ({template.get('minutiae_count', 0)} minutiae)")

    # An identity needs >=2 usable impressions to contribute genuine pairs.
    out = {k: v for k, v in out.items() if v}
    return out, dropped


# ===========================================================================
# Pair scoring
# ===========================================================================

@dataclass
class PairScore:
    a: str
    b: str
    label: str   # "genuine" | "impostor"
    score: float


def score_pairs(
    templates: dict[str, list[tuple[Path, dict]]],
    max_impostor: int,
    seed: int,
) -> list[PairScore]:
    """Compute all genuine pairs and a random sample of impostor pairs."""
    from app.services.sourceafis_service import match_templates

    rng = random.Random(seed)
    items: list[tuple[str, Path, dict]] = [
        (identity, path, tmpl)
        for identity, lst in templates.items()
        for (path, tmpl) in lst
    ]

    # --- genuine: every within-identity impression pair ---
    genuine: list[PairScore] = []
    for identity, lst in templates.items():
        for (pa, ta), (pb, tb) in itertools.combinations(lst, 2):
            genuine.append(PairScore(pa.name, pb.name, "genuine",
                                     float(match_templates(ta, tb))))

    # --- impostor: pairs across different identities, sampled ---
    cross = [
        (i, j) for i, j in itertools.combinations(range(len(items)), 2)
        if items[i][0] != items[j][0]
    ]
    rng.shuffle(cross)
    if max_impostor > 0:
        cross = cross[:max_impostor]

    impostor: list[PairScore] = []
    for i, j in cross:
        _, pa, ta = items[i]
        _, pb, tb = items[j]
        impostor.append(PairScore(pa.name, pb.name, "impostor",
                                  float(match_templates(ta, tb))))

    return genuine + impostor


# ===========================================================================
# Metrics
# ===========================================================================

@dataclass
class Metrics:
    genuine_n: int
    impostor_n: int
    genuine_mean: float
    genuine_std: float
    impostor_mean: float
    impostor_std: float
    eer: float
    eer_threshold: float
    far_targets: dict       # {"0.01": {"threshold": .., "far": .., "frr": ..}, ...}
    roc: list               # [(threshold, far, frr), ...]


def _mean_std(xs: list[float]) -> tuple[float, float]:
    if not xs:
        return 0.0, 0.0
    n = len(xs)
    mean = sum(xs) / n
    var = sum((x - mean) ** 2 for x in xs) / n
    return mean, var ** 0.5


def compute_metrics(
    genuine: list[float],
    impostor: list[float],
    step: float,
    far_targets: list[float],
) -> Metrics:
    """Build the FAR/FRR curve and derive EER + operating points."""
    if not genuine or not impostor:
        raise ValueError("need at least one genuine and one impostor score")

    g_n, i_n = len(genuine), len(impostor)

    def far(t: float) -> float:  # impostor accepted (score >= t)
        return sum(1 for s in impostor if s >= t) / i_n

    def frr(t: float) -> float:  # genuine rejected (score < t)
        return sum(1 for s in genuine if s < t) / g_n

    lo = min(min(genuine), min(impostor))
    hi = max(max(genuine), max(impostor))
    # Grid from lo to hi inclusive; +step so the top boundary (FAR=0) is covered.
    n_steps = max(1, int((hi - lo) / step) + 2)
    grid = [round(lo + k * step, 6) for k in range(n_steps)]

    roc = [(t, far(t), frr(t)) for t in grid]

    # EER: grid point minimising |FAR - FRR|.
    eer_t, fa, fr = min(roc, key=lambda r: abs(r[1] - r[2]))
    eer = (fa + fr) / 2

    targets: dict[str, dict] = {}
    for target in far_targets:
        # smallest threshold whose FAR <= target (FAR is monotone non-increasing in t)
        chosen = next((t for t, fa_, _ in roc if fa_ <= target), hi)
        targets[f"{target:g}"] = {
            "threshold": round(chosen, 4),
            "far": round(far(chosen), 6),
            "frr": round(frr(chosen), 6),
        }

    gm, gs = _mean_std(genuine)
    im, is_ = _mean_std(impostor)

    return Metrics(
        genuine_n=g_n, impostor_n=i_n,
        genuine_mean=round(gm, 3), genuine_std=round(gs, 3),
        impostor_mean=round(im, 3), impostor_std=round(is_, 3),
        eer=round(eer, 6), eer_threshold=round(eer_t, 4),
        far_targets=targets,
        roc=[(round(t, 4), round(fa_, 6), round(fr_, 6)) for t, fa_, fr_ in roc],
    )


# ===========================================================================
# Reporting
# ===========================================================================

def print_summary(m: Metrics) -> None:
    line = "─" * 58
    print(f"\n{line}")
    print("  FAR / FRR CALIBRATION SUMMARY")
    print(line)
    print(f"  genuine pairs   : {m.genuine_n:>6}   "
          f"mean {m.genuine_mean:6.2f}  sd {m.genuine_std:5.2f}")
    print(f"  impostor pairs  : {m.impostor_n:>6}   "
          f"mean {m.impostor_mean:6.2f}  sd {m.impostor_std:5.2f}")
    sep = m.genuine_mean - m.impostor_mean
    print(f"  separation      : {sep:6.2f}  (genuine_mean − impostor_mean)")
    print(line)
    print(f"  EER             : {m.eer*100:6.2f}%   at threshold {m.eer_threshold}")
    print("  operating points (pick threshold for a target false-accept rate):")
    print(f"    {'target FAR':>10} | {'threshold':>9} | {'actual FAR':>10} | {'FRR':>7}")
    for key, v in m.far_targets.items():
        tgt = float(key)
        print(f"    {tgt*100:9.2f}% | {v['threshold']:9.2f} | "
              f"{v['far']*100:9.2f}% | {v['frr']*100:6.2f}%")
    print(line)
    print("  Set FINGERPRINT_MATCH_THRESHOLD (in laravel/.env and python-service/.env)")
    print("  to the threshold whose FAR your deployment tolerates.")
    print("  Lower threshold = fewer false rejects, more false accepts.")
    print(f"{line}\n")


def write_outputs(out_dir: Path, pairs: list[PairScore], m: Metrics, meta: dict) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    with (out_dir / "scores.csv").open("w") as f:
        f.write("a,b,label,score\n")
        for p in pairs:
            f.write(f"{p.a},{p.b},{p.label},{p.score}\n")

    with (out_dir / "roc.csv").open("w") as f:
        f.write("threshold,far,frr\n")
        for t, fa, fr in m.roc:
            f.write(f"{t},{fa},{fr}\n")

    report = {"meta": meta, "metrics": asdict(m)}
    with (out_dir / "calibration_report.json").open("w") as f:
        json.dump(report, f, indent=2)

    _maybe_plot(out_dir, m)
    print(f"Wrote scores.csv, roc.csv, calibration_report.json to {out_dir}/")


def _maybe_plot(out_dir: Path, m: Metrics) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        print("  (matplotlib not installed — skipping plots)", file=sys.stderr)
        return

    ts = [r[0] for r in m.roc]
    fars = [r[1] * 100 for r in m.roc]
    frrs = [r[2] * 100 for r in m.roc]

    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(ts, fars, label="FAR", color="#dc2626")
    ax.plot(ts, frrs, label="FRR", color="#2563eb")
    ax.axvline(m.eer_threshold, color="#6b7280", ls="--", lw=1,
               label=f"EER {m.eer*100:.2f}% @ {m.eer_threshold}")
    ax.set_xlabel("Match threshold")
    ax.set_ylabel("Error rate (%)")
    ax.set_title("FAR / FRR vs threshold")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_dir / "far_frr.png", dpi=130)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(5, 5))
    ax.plot(fars, [100 - f for f in frrs], color="#16a34a")  # ROC: FAR vs (1-FRR)
    ax.set_xlabel("FAR (%)")
    ax.set_ylabel("Genuine accept rate (%)")
    ax.set_title("ROC")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_dir / "roc.png", dpi=130)
    plt.close(fig)
    print("  wrote far_frr.png and roc.png")


# ===========================================================================
# Self-test — validates the metric math with no dataset / no OpenCV
# ===========================================================================

def self_test() -> int:
    """Synthesise well-separated distributions and assert the metrics are sane."""
    rng = random.Random(7)
    genuine = [max(0.0, min(100.0, rng.gauss(45, 8))) for _ in range(400)]
    impostor = [max(0.0, min(100.0, rng.gauss(8, 5))) for _ in range(4000)]

    m = compute_metrics(genuine, impostor, step=0.5, far_targets=[0.01, 0.001])
    print_summary(m)

    ok = True
    # Distributions are well separated, so EER should be very small.
    if not (m.eer < 0.05):
        print(f"FAIL: EER unexpectedly high: {m.eer}", file=sys.stderr); ok = False
    # FAR is monotone non-increasing along the threshold grid.
    fars = [fa for _, fa, _ in m.roc]
    if any(b - a > 1e-9 for a, b in zip(fars, fars[1:])):
        print("FAIL: FAR not monotone non-increasing in threshold", file=sys.stderr); ok = False
    # At the 1% FAR operating point, actual FAR must not exceed the target.
    if m.far_targets["0.01"]["far"] > 0.01 + 1e-9:
        print("FAIL: 1% FAR operating point exceeds target", file=sys.stderr); ok = False

    print("SELF-TEST:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


# ===========================================================================
# CLI
# ===========================================================================

def main() -> int:
    ap = argparse.ArgumentParser(description="Fingerprint FAR/FRR calibration harness")
    ap.add_argument("--data", type=Path, help="Root directory of labelled fingerprint captures")
    ap.add_argument("--out", type=Path, default=Path("calibration_out"),
                    help="Output directory (default: ./calibration_out)")
    ap.add_argument("--max-impostor", type=int, default=20000,
                    help="Cap on sampled impostor pairs (0 = all; default 20000)")
    ap.add_argument("--seed", type=int, default=42, help="RNG seed for impostor sampling")
    ap.add_argument("--step", type=float, default=0.5, help="Threshold grid step (default 0.5)")
    ap.add_argument("--far-targets", type=float, nargs="+", default=[0.01, 0.001],
                    help="Target FARs to report operating thresholds for (default 0.01 0.001)")
    ap.add_argument("--no-enhance", action="store_true",
                    help="Skip the phone-tuned CLAHE+Gabor stages (isolate the "
                         "matcher; use for clean contact-sensor sets like SOCOFing/FVC)")
    ap.add_argument("--identity-scheme", choices=sorted(IDENTITY_SCHEMES), default="generic",
                    help="How to derive identity keys from filenames (default: generic "
                         "dir+stem parser; 'ridgebase-contactless' parses RidgeBase's "
                         "Task1 Contactless filenames and skips non-matching files)")
    ap.add_argument("--self-test", action="store_true",
                    help="Validate the metric math on synthetic data and exit")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if not args.data:
        ap.error("--data is required (or use --self-test)")
    if not args.data.is_dir():
        ap.error(f"--data is not a directory: {args.data}")

    print(f"Scanning {args.data} (identity scheme: {args.identity_scheme}) ...")
    groups = discover_images(args.data, identity_fn=IDENTITY_SCHEMES[args.identity_scheme])
    n_imgs = sum(len(v) for v in groups.values())
    print(f"Found {n_imgs} images across {len(groups)} identities.")
    if n_imgs == 0:
        ap.error("no images found — check the directory and file extensions")

    enhance = not args.no_enhance
    print(f"Extracting templates ({'full pipeline' if enhance else 'matcher-only, --no-enhance'}) ...")
    templates, dropped = build_templates(groups, enhance=enhance)

    usable_ids = len(templates)
    genuine_capable = sum(1 for v in templates.values() if len(v) >= 2)
    print(f"Usable: {sum(len(v) for v in templates.values())} images, "
          f"{usable_ids} identities ({genuine_capable} with >=2 impressions), "
          f"{dropped} dropped.")
    if genuine_capable == 0:
        ap.error("no identity has >=2 usable impressions — cannot form genuine pairs")
    if usable_ids < 2:
        ap.error("need >=2 identities to form impostor pairs")

    print("Scoring pairs ...")
    pairs = score_pairs(templates, args.max_impostor, args.seed)
    genuine = [p.score for p in pairs if p.label == "genuine"]
    impostor = [p.score for p in pairs if p.label == "impostor"]

    m = compute_metrics(genuine, impostor, args.step, args.far_targets)
    print_summary(m)

    meta = {
        "data": str(args.data),
        "images_found": n_imgs,
        "identities_found": len(groups),
        "images_usable": sum(len(v) for v in templates.values()),
        "identities_usable": usable_ids,
        "images_dropped": dropped,
        "max_impostor": args.max_impostor,
        "seed": args.seed,
        "step": args.step,
        "far_targets": args.far_targets,
        "enhance": enhance,
        "identity_scheme": args.identity_scheme,
    }
    write_outputs(args.out, pairs, m, meta)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
