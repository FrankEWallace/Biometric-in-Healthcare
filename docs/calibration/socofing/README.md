# SOCOFing Calibration Results (2026-07)

FAR/FRR calibration of the minutiae matcher against a SOCOFing subset
(1000 identities, ~3000 images), run with `python-service/tools/calibrate_far_frr.py`
(seed 42, 20,000 impostor pairs, threshold step 0.5).

Two passes, identical data and pairs — only the preprocessing differs:

| Metric | `socofing_noenhance/` (raw) | `socofing_enhance/` (Gabor) |
|---|---|---|
| EER | **13.5%** (thr 15.0) | 20.3% (thr 14.5) |
| Threshold @ FAR 1% | 24.0 (FRR 24.8%) | 22.5 (FRR 41.9%) |
| Threshold @ FAR 0.1% | 33.5 (FRR 35.1%) | 26.5 (FRR 49.9%) |
| Genuine score mean ± std | 55.2 ± 32.3 | 34.8 ± 22.1 |
| Impostor score mean ± std | 10.4 ± 4.8 | 12.6 ± 3.4 |

## Key findings

1. **Gabor enhancement hurts accuracy on SOCOFing** — it compresses genuine
   scores (55.2 → 34.8 mean) more than it suppresses impostor scores, degrading
   separation at every operating point. Sensor-captured SOCOFing images are
   already high-contrast ridge maps; enhancement is only expected to help on
   noisy camera-captured (contactless) input.
2. **Deployed threshold 32.0** (`FINGERPRINT_MATCH_THRESHOLD`, no-enhance
   scale): FAR ≈ 0.14%, FRR ≈ 33% on SOCOFing. For a target FAR of 1%,
   threshold 24.0 would roughly cut FRR to 25%.
3. Caveat for the write-up: SOCOFing is contact/sensor data — thresholds do not
   transfer directly to camera-captured finger photos (see
   `docs/` contactless dataset notes). Treat these as matcher-quality evidence,
   not deployment calibration.

Each result folder contains `calibration_report.json` (full metrics + ROC
table), `scores.csv`, `roc.csv`, and rendered `roc.png` / `far_frr.png`.
`pass1_noenhance.log` / `pass2_enhance.log` are the full run logs.
