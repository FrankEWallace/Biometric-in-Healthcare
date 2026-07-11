# Contactless four-finger threshold — operating point decision (2026-07-12)

> Status: **ADOPTED, pending own-domain validation.** This records *why* the
> shipped `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=57.5` is defensible without a
> fresh own-capture calibration, and what would change that.

## Decision

Ship the contactless four-finger accept threshold at **57.5** (the FAR≈1%
operating point), taken from the RidgeBase Test evaluation run **through this
system's own production pipeline** — not from a newly collected own-capture set.

## Why not calibrate on our own captures now

Two independent reasons:

1. **A learned embedding is trained, not tuned by us.** The Ridgeformer encoder
   was trained on large public contactless data; we use it as-is (frozen ONNX).
   The only thing we choose is the *threshold* — a single cutoff on the
   genuine-vs-impostor score distribution. That is a much smaller quantity than
   the model, and it has already been measured on our pipeline (below).

2. **A 10–20 identity own-set is statistically underpowered for a 1% FAR.**
   Estimating a false-accept rate of 1% needs on the order of hundreds–thousands
   of impostor comparisons; 10–20 identities yield a handful of genuine pairs and
   wide confidence intervals — you could not distinguish 1% FAR from 5% FAR. Such
   a set is a useful *sanity check*, not a calibration source. Re-deriving the
   threshold from it would produce a **worse**, noisier number than the one we
   already have.

## The number we already have (service-path eval)

From `docs/calibration/ridgebase/ridgeformer_eval.md` — the released Ridgeformer
encoder exported to ONNX and run through the **production `EmbeddingMatcher`**
(our preprocessing + our four-finger fusion + our 0–100 scoring), reproducing the
torch reference within 0.08% EER:

| Metric | Four-finger fused (our pipeline) |
|---|---|
| EER | 8.85% @ fused threshold 45.5 |
| **Threshold @ FAR≈1%** | **57.55** (FRR 12.3%) |
| Genuine score mean ± sd | 77.6 ± 17.4 |
| Impostor score mean ± sd | 25.2 ± 14.3 |

We ship **57.5 (FAR≈1%)**, not the EER point (~45.5), on purpose: in a hospital a
false accept means the **wrong patient**, so we bias toward false-reject →
manual review. The placeholder-safe gate also guarantees the system only
auto-decides when the embedding matcher actually ran; on the minutiae fallback it
stays `needs_review` regardless of this value.

## The honest caveat

This threshold is validated on **RidgeBase** contactless crops, not on images
captured by *this app's own camera pipeline* (`FingerprintLivenessCameraScreen`).
The one remaining unknown is **domain shift** — whether real phone captures in
the field distribute like RidgeBase crops. Because the direction of any shift is
unknown and false-accept is the dangerous error, the conservative FAR≈1% choice
is the right hedge, but the actual field FAR/FRR is not yet measured.

Do **not** describe 57.5 as "calibrated on own-domain data." It is an operating
point *adopted* from a faithful service-path evaluation, pending field
validation.

## Revalidation trigger

Re-run the four-finger calibration (`tools/validate_embedding_fourfinger.py`
shape) and update this file + `.env.example` when either becomes available:

- **NIDA / NHIF** grant real, labelled Tanzanian biometric data, or
- enough **own field captures** accumulate through the app's capture screen to
  estimate FAR at the target operating point with confidence (hundreds of
  impostor pairs, not tens).

Also re-run whenever the capture pipeline changes (resolution, preprocessing,
segmentation, or the ONNX model file) — the threshold tracks the algorithm.
