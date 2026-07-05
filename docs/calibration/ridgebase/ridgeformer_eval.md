# Ridgeformer embedding — reproduced on our RidgeBase Test split (2026-07-05)

We ran the released **Ridgeformer** Stage-1 checkpoint (`phase1_scratch.pt`,
CC-BY-NC 4.0, github.com/KNITPhoenix/Ridgeformer) on the **same** RidgeBase
Task1 Test split our minutiae matcher failed on, to confirm a learned embedding
actually solves the contactless problem on *our* data before integrating it.

## Result

| Scenario | Ridgeformer (this run, our data) | Ridgeformer (paper) | Our minutiae matcher |
|---|---|---|---|
| **C2CL EER** (contactless probe vs contact gallery) | **5.96%** | 5.25% | ~50% (chance) |
| **CL2CL EER** (contactless vs contactless) | **8.13%** | 7.60% | ~46% (chance) |
| C2CL ROC-AUC | 97.95% | — | ~50% |
| CL2CL ROC-AUC | 97.38% | — | ~50% |
| C2CL R@1 (identification) | 70.57% | 69.90% | ~1% |
| CL2CL R@1 | 91.70% | 100% | ~2.5% |

The reproduction lands within ~0.5–0.7% EER of the published numbers — normal
run/protocol variance. **This is the whole thesis, confirmed on our own data:**
classical minutiae is non-discriminative on contactless finger photos (EER ~46–50%,
coin-flip), while the learned embedding is a genuinely usable biometric
(EER ~6–8%) — a ~6× improvement. This is exactly why the matcher interface routes
the contactless path to an embedding rather than trying to fix minutiae.

## How it was run (reproducible)

- Weights: `phase1_scratch.pt` from the HuggingFace model card `spandey8/Ridgeformer`
  (1.23 GB). Loaded with `missing=0, unexpected=0` keys — a clean, complete load.
- Model: `SwinModel_domain_agnostic` = ViT-Large/16 @224 (timm 0.5.0, their shipped
  wheel) with `linear_cl` projection head. Embedding = mean over the 197 post-norm
  ViT tokens → `linear_cl` → 1024-d, L2-normalised.
- Data: our `datasets/ridgebase/Task1/Test` — 2229 contactless PNGs, 200 contact BMPs,
  200 identities. Test transform: `ToTensor → Resize(224) → Grayscale(3ch)` (no
  ImageNet mean/std) + a hand-orientation rotate/flip (right vs left).
- Scoring (from upstream `rb_evaluation_phase1.py`): contact gallery averaged per
  identity; C2CL score = cosine + 0.1·(−L2); CL2CL = cosine on the upper triangle.
- Hardware: Apple MPS, ~11 min for all embeddings on CPU-class laptop silicon.
- Runner: `third_party/ridgeformer/rb_eval_cpu.py` (a CPU/MPS port of the upstream
  cuda-only eval; only device + a token-sequence `forward` shim differ). The
  Ridgeformer code + weights are third-party (CC-BY-NC) and gitignored under
  `third_party/` — not committed.

## Implication for the build

This retires the last risk on the contactless roadmap: the embedding path is not
just theoretically better, it works on *our* dataset.

## ONNX export + service integration (DONE 2026-07-05)

The encoder is now exported and wired into the production `EmbeddingMatcher`.

- **Export** (`third_party/ridgeformer/export_onnx.py`, gitignored): wraps
  `get_embeddings(x,"contactless")` + L2-norm and exports to ONNX opset 17 with a
  dynamic batch axis. The shared-encoder design (`swin_cb is swin_cl`, both use
  `linear_cl`) means **one ONNX model embeds both contact and contactless** — so
  the same matcher does CL2CL *and* C2CL. Output goes to the gitignored
  `python-service/models/contactless_embedding.onnx` (~1.1 GB).
  Command: `PRETRAINED=0 .venv/bin/python export_onnx.py <out.onnx>`.
- **Parity**: ONNX vs torch on the same input — `max_abs_diff 8.5e-7`,
  `cosine 1.000000`; dynamic batch verified.
- **Preprocessing reconciliation**: `EmbeddingMatcher._preprocess` now matches the
  training transform (grayscale→3ch with torchvision RGB weights on cv2 BGR
  channels, resize 224 via **INTER_AREA**, /255, no mean/std, optional
  hand-orientation rotate/flip). Verified vs the torch reference transform at
  **cosine ≥0.997** (INTER_AREA; plain INTER_LINEAR was only ~0.987).
- **Routing**: with the model present, `get_matcher("contactless")` returns the
  embedding matcher; absent, it falls back to minutiae. Set `EMBEDDING_MODEL_PATH`
  to relocate the model.
- **Validation harness**: `python-service/tools/validate_embedding_ridgebase.py`
  runs the whole SERVICE path (ONNX + our preprocessing + our fusion scoring)
  over RidgeBase Test to reproduce CL2CL EER and derive the contactless threshold.

## Service-path validation (DONE 2026-07-05)

Ran `tools/validate_embedding_ridgebase.py` over all 2229 RidgeBase Test
contactless crops through the production `EmbeddingMatcher` (ONNX + our
preprocessing + our cosine→0-100 scoring):

| Metric | Service pipeline (ONNX) | Reference (torch) |
|---|---|---|
| **CL2CL EER** | **8.05%** | 8.13% |
| Genuine score mean ± sd | 77.5 ± 19.1 | — |
| Impostor score mean ± sd | 16.5 ± 16.0 | — |
| EER threshold (0–100 scale) | **42.35** | — |
| Threshold @ FAR≈1% | 61.11 (FRR 15.1%) | — |

Our own pipeline reproduces the reference within 0.08% EER — the ONNX export and
preprocessing are faithful. Contrast: minutiae CL2CL EER here was ~46%.

### Setting the contactless threshold (operating-point choice)
`services.fingerprint.contactless_match_threshold` (env
`FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD`) is on the **fused** hand score, still
NULL by default (verify-hand stays advisory until set). Guidance:
- **~42** = EER point (balanced ~8% FAR/FRR, single-finger).
- **~61** = FAR≈1% (conservative; recommended for healthcare, where a false
  accept = wrong patient). Four-finger fusion tightens the genuine/impostor gap,
  so a single-finger threshold applied to fused scores is *conservative* (lower
  FRR at the same FAR) — a four-finger embedding calibration would refine it.

## Remaining
Pick and set the contactless threshold above (policy call: FAR vs FRR), optionally
run a four-finger embedding calibration to refine it, and build the Flutter
hand-capture screen (toolchain not installed).
