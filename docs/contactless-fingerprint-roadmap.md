# Contactless Four-Finger Fingerprint — Implementation Roadmap

Status: planning (2026-07-05). Owning context: `docs/calibration/ridgebase/README.md`
(evidence) and the memory notes on four-finger architecture.

## Why this roadmap exists

Calibration on RidgeBase proved the current **minutiae** matcher fails on contactless
finger photos in every scenario (CL2CL EER ~46%, four-finger fusion 42–47%, C2CL = chance).
Even world-class commercial minutiae (VeriFinger) caps ~20% EER on this domain; a learned
deep embedding (Ridgeformer) reaches ~7.6%. Meanwhile the app only captures/matches **one
finger**, though the intended UX is a photo of the whole hand. This roadmap moves us to a
four-finger contactless pipeline backed by a domain-appropriate matcher — without throwing
away what already works.

## Guiding decisions (agreed)

1. **Hybrid, domain-routed matching — do not replace, add.**
   | Path | Matcher | Rationale |
   |---|---|---|
   | contact ↔ contact | keep **minutiae** (ISO 19794-2) | already strong (SOCOFing 13.5% EER), standards-interoperable (NIDA/legacy AFIS), explainable, legally mature |
   | contactless / C2CL | add **learned embedding** | the only thing that works on finger photos |
2. **Functionality first, accuracy second** (per CLAUDE.md). Build the four-finger pipeline
   with a *swappable* matcher so it runs end-to-end on the minutiae placeholder, then swap in
   the embedding for accuracy. Never demo accuracy on the placeholder.
3. **Layer modalities (Selcom lesson).** Don't bet on fingerprint alone. Combine with face
   (already in repo via InsightFace + FAISS), geofencing, and anchor authoritative identity to
   the contact/NIDA side.

## Phases

### Phase 1 — Four-finger capture + segmentation  (functionality)
- **Goal:** nurse photographs the hand; system yields 4 clean per-finger crops.
- **Tasks:**
  - Mobile capture: hand-framing overlay, rear camera + flash (IDEMIA 4F convention:
    index/middle/ring/little; thumb separate or skipped).
  - Segmentation: locate 4 fingertips and crop. Candidate approaches — MediaPipe hand
    landmarks (on-device) or a lightweight fingertip detector; segment server-side first if
    on-device is slow. Target output = RidgeBase contactless crop format (so we keep testing
    on real labelled data).
  - Quality gating per finger (focus/exposure) before accept.
- **Deliverable:** capture screen produces 4 named crops + quality scores.
- **Depends on:** nothing (can start now). Flutter toolchain install still pending on this Mac.
- **Risks:** segmentation robustness across skin tones/lighting/backgrounds; thumb handling.
- **Exit criteria:** ≥95% of test-hand photos segment into 4 usable crops.

### Phase 2 — Four-finger enrollment + fused verify  (functionality, matcher-agnostic)
- **Goal:** store 4 templates/patient; verify by matching 4 and fusing.
- **Tasks:**
  - Define a **matcher interface** in the Python service: `extract(image) -> template`,
    `score(template, template) -> float`, with a `domain` tag (contact | contactless).
    Wire it to the existing minutiae matcher as the default implementation.
  - Enrollment: create 4 `fingerprints` rows/hand (`finger_position` already exists);
    extend the enroll flow + Laravel controllers to accept a 4-crop payload.
  - Verify: embed 4 probe fingers, match each to its enrolled counterpart, **fuse** scores
    (lift the mean-fusion logic from `tools/ridgebase_eval.py`; make fusion pluggable).
  - Keep liveness (optical-flow) and geofencing in the flow unchanged.
- **Deliverable:** end-to-end four-finger enroll + verify running on the minutiae placeholder.
- **Depends on:** Phase 1 (crops) for real input; interface can be built in parallel.
- **Risks:** finger-correspondence across captures (index↔index); DB migration for 4 rows.
- **Exit criteria:** full enroll→verify demo works; pipeline is accuracy-agnostic and logs
  per-finger + fused scores.

### Phase 3 — Learned contactless embedding  (accuracy)
- **Goal:** replace the contactless-path matcher with an embedding; hit usable EER.
- **Tasks:**
  - Evaluate Ridgeformer (arXiv:2506.01806) / a C2CL model: released weights, license, and
    whether it runs on CPU via ONNX (InsightFace precedent says plausible) or needs GPU.
  - Slot it behind the Phase-2 interface as the `contactless` implementation; store embeddings
    and index with **FAISS** (already used for face → helps 1:N scaling).
  - Re-run the FAR/FRR + rank-1 harness (`ridgebase_eval.py`) on RidgeBase to confirm we
    approach the ~7.6% single-finger benchmark; then measure four-finger fusion on top.
  - Set the contactless threshold from *these* numbers (never the minutiae 32.0).
- **Deliverable:** contactless verify at benchmark-competitive accuracy; documented thresholds.
- **Depends on:** Phase 2 interface.
- **Risks:** **domain generalization** — Ridgeformer trained on 88 non-Tanzanian subjects; may
  degrade on local captures with no local labelled data to fine-tune. Model governance
  (weights, versioning, licence). Loss of ISO-template exportability on the contactless path.
- **Exit criteria:** contactless EER within a stated margin of the published benchmark on
  RidgeBase Test; latency within target on target hardware.

### Phase 4 — Layered / integrated identity  (robustness)
- **Goal:** Selcom-style multi-factor; anchor to authoritative contact DB / NIDA.
- **Tasks:**
  - Wire the existing multimodal decision matrix (face + fingerprint + geofence) to combine
    signals rather than trusting fingerprint alone.
  - C2CL path: match phone photo against enrolled **contact** records (existing hospital DB /
    NIDA). This is why C2CL matters — decide export vs internal-match architecture.
  - Confirm PAD/liveness adequacy for finger photos (photo-of-photo attack).
- **Deliverable:** integrated verification with a defensible trust model.
- **Depends on:** Phases 2–3.
- **Risks:** NIDA/hospital-DB integration access + legal/consent; presentation-attack coverage.

## Open questions to pin down (affect sizing)
- **N** — enrolled patients per hospital (drives 1:N FAR budget and FAISS need).
- **Latency target** — acceptable verify time on target device/server.
- **Integration target** — do we export templates to NIDA/legacy AFIS (needs ISO minutiae) or
  match everything internally (embeddings fine)? This decides the Phase-4 architecture.
- **Local data** — is any labelled Tanzanian capture data obtainable for Phase-3 fine-tuning?

## Recommended sequencing
Start **Phase 1 + the Phase-2 interface** (functionality-first, demoable, nothing wasted).
Run **Phase 3 evaluation** (can Ridgeformer weights load & run?) in parallel as a spike, since
its answer determines the accuracy ceiling. Hold Phase 4 until 2–3 land.
