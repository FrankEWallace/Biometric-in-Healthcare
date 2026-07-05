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

Each result folder contains `calibration_report.json` (full metrics + ROC table),
`scores.csv`, `roc.csv`, rendered `roc.png` / `far_frr.png`, and `run.log`.
Raw RidgeBase data stays local (gitignored under `datasets/`).
