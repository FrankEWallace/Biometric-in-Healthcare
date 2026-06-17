#!/usr/bin/env python3
"""
Regenerate FAR/FRR + ROC plots from an existing calibration_report.json,
without re-extracting templates. Reuses the harness's plotting code.

Usage:
    python tools/plot_calibration.py calibration_out/socofing_noenhance [more_dirs...]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from tools.calibrate_far_frr import Metrics, _maybe_plot  # noqa: E402


def plot_dir(out_dir: Path) -> None:
    report = json.loads((out_dir / "calibration_report.json").read_text())
    m = Metrics(**report["metrics"])
    # roc came back from JSON as lists; _maybe_plot only indexes [0]/[1]/[2] so that's fine.
    _maybe_plot(out_dir, m)
    print(f"  {out_dir}: EER {m.eer*100:.2f}% @ {m.eer_threshold}")


def main() -> int:
    dirs = [Path(d) for d in sys.argv[1:]]
    if not dirs:
        print("usage: plot_calibration.py <report_dir> [report_dir...]", file=sys.stderr)
        return 2
    for d in dirs:
        if not (d / "calibration_report.json").is_file():
            print(f"  ! {d}: no calibration_report.json", file=sys.stderr)
            continue
        plot_dir(d)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
