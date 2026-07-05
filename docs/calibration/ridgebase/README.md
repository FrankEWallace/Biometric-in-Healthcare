# RidgeBase Contactless Calibration Results (2026-07)

FAR/FRR calibration of the minutiae matcher against **RidgeBase Task1
`Test/Contactless`** (200 identities, 2,229 finger-photo images from 2 smartphones
× 3 backgrounds), run with `python-service/tools/calibrate_far_frr.py`
(`--identity-scheme ridgebase-contactless`, seed 42, 20,000 impostor pairs,
threshold step 0.5). Scenario: **CL2CL** (contactless→contactless), which matches
our production flow where both enrollment and verification are phone captures.

Two passes, identical data and pairs — only preprocessing differs:

| Metric | `cl2cl_test_noenhance/` | `cl2cl_test_enhance/` (Gabor) |
|---|---|---|
| **EER** | **47.5%** (thr 18.0) | **46.0%** (thr 26.5) |
| d′ (discriminability) | 0.15 | 0.19 |
| Genuine score mean ± std | 19.4 ± 10.1 | 28.0 ± 9.3 |
| Impostor score mean ± std | 18.0 ± 9.0 | 26.4 ± 8.7 |
| Separation (genuine − impostor mean) | 1.4 | 1.7 |
| Impostors ≥ genuine median | 48% | 46% |
| Threshold @ FAR 1% | 44.5 (FRR **98.5%**) | 48.5 (FRR **98.6%**) |
| Threshold @ FAR 0.1% | 52.5 (FRR 99.8%) | 54.5 (FRR 99.7%) |
| Genuine pairs / Impostor pairs | 11,641 / 20,000 | 11,782 / 20,000 |

## Headline finding: the minutiae matcher does not work on contactless finger photos

An **EER of ~46–47% is coin-flip** (50% = pure chance). The genuine and impostor
score distributions almost completely overlap (d′ ≈ 0.15–0.19; a usable biometric
wants d′ > 3). At any threshold that admits only 1% of impostors, it *rejects
~98.5% of genuine matches*. **There is no usable operating point** — this pipeline
cannot do contactless 1:1 verification at acceptable accuracy.

### This is a real result, not a harness/parsing bug

Positive controls confirm the matcher itself is sound and the data is grouped
correctly:

- **Self-match** (a template against itself) scores **100.0**, as expected.
- Identity grouping is correct: all 200 identities parsed cleanly into ≥2
  impressions each; 0–14 images dropped for unreadable minutiae.
- The failure is at the **feature level**: contactless images saturate the
  minutiae extractor (≈50 spurious minutiae on nearly every image — texture/noise,
  not stable ridge features), so genuine and impostor templates look alike.

### Why (matches the prior-work research)

Contactless finger *photos* differ fundamentally from contact prints —
ridge-valley inversion (light ridges on skin vs dark ridges on a sensor), unknown
DPI/scale, perspective distortion, and no skin-flattening deformation. Classical
minutiae extraction, which our pipeline uses, is unreliable on this input. This is
exactly why the contactless finger-photo field (C2CL, ContactlessNet,
Fusion2Print) uses **learned deep embeddings**, not minutiae, and why NISTIR 8307
reports only 60–70% single-finger contactless accuracy even for commercial systems.

## Contrast with SOCOFing (contact-domain, committed under `docs/calibration/socofing/`)

| | SOCOFing (contact) no-enhance | RidgeBase (contactless) enhance |
|---|---|---|
| EER | **13.5%** | **46.0%** |
| d′ | ~1.9 | ~0.19 |
| Genuine / impostor mean | 55.2 / 10.4 | 28.0 / 26.4 |

The **same matcher** goes from workable on contact prints (clear separation,
EER 13.5%) to non-discriminative on contactless photos (EER 46%). This is not a
threshold that needs re-tuning — the score signal itself is absent in the
contactless domain.

## Enhancement helps marginally, but nowhere near usable

CLAHE+Gabor enhancement improves EER from 47.5% → 46.0% and d′ from 0.15 → 0.19 —
directionally the opposite of SOCOFing (where enhancement *hurt* clean contact
prints), consistent with "enhancement helps noisy camera input." But the effect is
tiny relative to the gap that needs closing.

## Implications

1. **Do not set `FINGERPRINT_MATCH_THRESHOLD` from these results.** No threshold
   yields acceptable FAR/FRR on contactless. The committed 32.0 is a
   SOCOFing/contact number and is meaningless for the camera path.
2. **The contactless path needs a different matcher** (a learned embedding model,
   e.g. a C2CL/ContactlessNet-style network) to be viable. Minutiae matching is
   validated only for the contact domain here.
3. **For the FYP write-up**, this is a defensible, honest negative result: report
   it with the NISTIR 8307 framing (single-finger contactless is hard) and cite it
   as motivation for the embedding approach or for scoping the demo to the
   like-to-like case.

## Four-finger fusion (does combining fingers rescue it?)

A phone photo of a hand already contains 4 fingers, so we tested fusing the 4
per-finger scores into one hand score (`ridgebase_eval.py` four-finger mode, mean
fusion, RidgeBase Task1 Test/Contactless).

| Metric | Single finger (enhance) | Four-finger fused (enhance) |
|---|---|---|
| EER | 46.0% | **41.9%** |
| Separation | 1.66 | 2.02 |
| d′ | 0.19 | **0.36** |

Fusion helps but does **not** rescue it. d′ almost exactly *doubled* (0.19 → 0.36),
which is the textbook √4 variance-reduction result: averaging 4 independent noisy
scores halves the noise. That confirms the fusion is working correctly **and** that
it is fundamentally capped — it reduces noise but cannot create signal. A usable
biometric needs d′ > 3 (~16× more); no amount of finger-fusion gets there from a
near-random per-finger matcher. Fusion is a multiplier on an already-good matcher,
not a fix for a bad one. At FAR 1% the four-finger FRR is still ~96%.

## The app is single-finger today (design gap)

Verified in code (`fingerprint_capture_screen.dart`, `fingerprint_service.dart`,
`VerificationController`, Python `/match`): capture, enrollment, and verification are
all **single-finger** — one probe template vs stored templates, keyed by
`finger_position` (default `right_index`). The `enroll-gallery` endpoint stores up to
3 captures of the **same** finger (a recall-boosting gallery), **not** four fingers.

This is a gap vs the intended UX (nurse photographs the whole hand). Four-finger
support would require: (1) capture → segment hand into 4 finger crops, (2) store 4
templates/patient, (3) match all 4 and fuse. The fusion logic is already prototyped
in `ridgebase_eval.py`.

## Benchmark context — this isn't just our code being bad

Published RidgeBase Task1 single-finger results (RidgeBase paper; Ridgeformer,
arXiv:2506.01806):

| Approach | CL2CL EER | C2CL EER |
|---|---|---|
| **Our minutiae matcher** | **~46%** | (pending) |
| VeriFinger (best commercial minutiae) | 19.7% | 18.9% |
| AdaCos deep-CNN baseline | 21.3% | — |
| **Ridgeformer (SOTA deep embedding)** | **7.6%** | **5.25%** |

Even **VeriFinger**, a world-class commercial minutiae matcher, caps around 20% EER on
contactless — minutiae is the wrong tool for this domain, period. A learned deep
embedding (Ridgeformer) reaches 7.6% single-finger; that is the realistic target for a
viable contactless path, with four-finger fusion as a further boost on top.

## How deployed systems actually authenticate (informs the design)

- **Selcom (Tanzania):** does not bet on contactless finger-photo accuracy — layers
  device fingerprint sensor + face recognition + PIN + **NIDA national-ID biometric
  verification** (authoritative check against the government DB).
- **IDEMIA 4F / commercial contactless:** capture 4 fingers at once with rear
  camera+flash, auto-segment, enhance, normalize to 500 DPI, and match against legacy
  **contact** databases (C2CL). Multi-finger reduces false accepts.
- **Lesson:** (1) C2CL matters — integration targets (existing hospital contact DBs,
  NIDA) are contact-based. (2) Don't rely on fingerprint alone; this repo already has
  multimodal verify (face + fingerprint) + geofencing — Selcom-style layering is the
  pragmatic, defensible design.

---

Each result folder contains `calibration_report.json` (full metrics + ROC table),
`scores.csv`, `roc.csv`, rendered `roc.png` / `far_frr.png`, and `run.log`.
Raw RidgeBase data stays local (gitignored under `datasets/`).
