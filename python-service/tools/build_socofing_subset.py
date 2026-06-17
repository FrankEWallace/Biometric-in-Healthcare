#!/usr/bin/env python3
"""
Build a calibration-ready subset from the SOCOFing dataset.

SOCOFing ships ONE real impression per finger (Real/) plus synthetically
altered variants (Altered/Altered-{Easy,Medium,Hard}/, suffixed _CR / _Obl /
_Zcut). The FAR/FRR harness needs >=2 impressions per identity and derives
identity by stripping a trailing *digit* sample index. This tool assembles a
flat directory where each finger becomes one identity with digit-suffixed
impressions the harness understands:

    <subject>_<H>_<finger>_1.BMP   <- Real
    <subject>_<H>_<finger>_2.BMP   <- 1st altered variant
    <subject>_<H>_<finger>_3.BMP   <- 2nd altered variant (optional)

Real fingers with no surviving altered variants (SOCOFing dropped a few during
alteration) contribute only an impostor sample, which is fine.

Usage:
    python tools/build_socofing_subset.py \
        --src datasets/socofing/SOCOFing \
        --out datasets/socofing_subset \
        --subjects 100 --level Easy --variants CR Zcut
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

# Real filename: "100__M_Left_index_finger.BMP"
_REAL_RE = re.compile(r"^(?P<sid>\d+)__(?P<rest>.+)_finger$", re.IGNORECASE)


def real_key(stem: str) -> tuple[int, str] | None:
    """Return (subject_id, finger_key) for a Real stem, or None if it doesn't match."""
    m = _REAL_RE.match(stem)
    if not m:
        return None
    return int(m.group("sid")), m.group("rest")  # rest e.g. "M_Left_index"


def main() -> int:
    ap = argparse.ArgumentParser(description="Assemble a SOCOFing calibration subset")
    ap.add_argument("--src", type=Path, required=True,
                    help="SOCOFing root (the dir containing Real/ and Altered/)")
    ap.add_argument("--out", type=Path, required=True, help="Output subset directory")
    ap.add_argument("--subjects", type=int, default=100,
                    help="Use subjects with id <= this (default 100; 0 = all 600)")
    ap.add_argument("--level", choices=["Easy", "Medium", "Hard"], default="Easy",
                    help="Altered difficulty to draw extra impressions from")
    ap.add_argument("--variants", nargs="+", default=["CR", "Zcut"],
                    choices=["CR", "Obl", "Zcut"],
                    help="Altered variants to add as impressions 2..k")
    ap.add_argument("--clean", action="store_true",
                    help="Wipe the output dir first")
    args = ap.parse_args()

    real_dir = args.src / "Real"
    alt_dir = args.src / "Altered" / f"Altered-{args.level}"
    if not real_dir.is_dir():
        ap.error(f"Real/ not found under {args.src}")
    if not alt_dir.is_dir():
        ap.error(f"{alt_dir} not found")

    if args.clean and args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True, exist_ok=True)

    copied_real = copied_alt = skipped = 0
    for real in sorted(real_dir.glob("*.BMP")):
        key = real_key(real.stem)
        if key is None:
            continue
        sid, finger = key
        if args.subjects and sid > args.subjects:
            continue

        base = f"{sid}__{finger}"  # collision-free identity stem
        shutil.copy2(real, args.out / f"{base}_1.BMP")
        copied_real += 1

        idx = 2
        for variant in args.variants:
            # e.g. "100__M_Left_index_finger_CR.BMP"
            cand = alt_dir / f"{sid}__{finger}_finger_{variant}.BMP"
            if cand.exists():
                shutil.copy2(cand, args.out / f"{base}_{idx}.BMP")
                copied_alt += 1
                idx += 1
            else:
                skipped += 1

    identities = copied_real
    print(f"Built subset in {args.out}/")
    print(f"  identities (fingers) : {identities}")
    print(f"  real impressions     : {copied_real}")
    print(f"  altered impressions  : {copied_alt}  (missing variants: {skipped})")
    print(f"  total images         : {copied_real + copied_alt}")
    if copied_alt == 0:
        print("  WARNING: no altered impressions copied — no genuine pairs possible",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
