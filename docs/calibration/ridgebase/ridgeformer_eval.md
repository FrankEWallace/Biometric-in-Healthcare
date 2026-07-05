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
just theoretically better, it works on *our* dataset. Remaining Phase-3 work is
integration only — export this encoder to ONNX, load it in
`python-service/app/services/embedding_service.py` (matching the preprocessing
above: grayscale-3ch, resize 224, no mean/std, hand-orientation normalisation),
then re-run `tools/ridgebase_eval.py` to set the contactless accept threshold.
