---
date: 2026-06-16
topic: Improving the contactless fingerprint recognition model
status: proposal — code changes #1 and #2 applied & verified; strategy items await user confirmation
outcome: Measure-then-improve plan — honestly evaluate the existing classical minutiae matcher
  on public datasets, unify thresholds, target ≤10% contactless EER with retune-before-replace
  (pretrained-only, CPU-only), frame 1:N as human-confirmed shortlist, scope PAD as future work,
  move liveness/geofence trust server-side.
---

# Improving the Contactless Fingerprint Model

> Research backing: NotebookLM notebook `86e43b2a-e7d3-4f09-bc97-fb3241a83a47`
> ("Contactless Fingerprint Patient ID — Prior Work & Datasets"), 49 cited sources.
> See memory: contactless_fingerprint_prior_work_and_datasets.md

## Strategy (Option C)
Measure the current classical crossing-number minutiae matcher honestly first; improve only if
the data demands it; deliver a documented "measured X → diagnosed → changed Y → re-measured Z" arc.

## Decisions

1. **Evaluation data.** SOCOFing = matcher-sanity baseline (free, large, contact-domain).
   IIITD ISPFDv2 (smartphone finger-photo) = headline contactless result; RidgeBase = backup;
   PolyU = stretch. Request access in parallel (long lead time) with SOCOFing as the fallback.

2. **SOCOFing protocol.** Run two ways: matcher-only via `--no-enhance`, and pipeline-as-is
   (exposes how much the phone-tuned enhancement degrades clean prints — itself a finding).
   Unaltered prints only for core FAR/FRR; altered variants parked as optional robustness test.

3. **Thresholds.** Unified the three live values (32.0 FingerprintService, 20.0 VerificationController,
   40.0 fingerprint.py) into one config value `FINGERPRINT_MATCH_THRESHOLD` (default 32.0). The
   harness then produces the empirical operating point (EER, threshold at target FAR ≤ 0.1%), which
   becomes the final config value in both .env files.

4. **Use-case framing.** 1:1 verification is the headline (target FAR ≤ 0.1%, full ROC/EER reported).
   1:N is human-confirmed shortlist only — never auto-identify. Report the FAR-vs-gallery-size N
   curve (N assumed ~hundreds — CONFIRM) to show the safety boundary explicitly.

5. **Improvement gate.** ≤10% contactless 1:1 EER ⇒ stay in phase B (calibrate + writeup).
   >10–15% ⇒ phase A, cheapest-fix-first: (a) multi-impression best-of-N, (b) retune
   enhancement/extraction/minutiae filtering, (c) only then a pretrained CPU-friendly contactless
   extractor. Hard constraints: classical first, pretrained-only, no from-scratch training, CPU-only.

6. **Multi-impression enrollment.** First retune lever if above the gate. Prove the FRR gain offline
   in the harness (best-of-N matching) BEFORE the schema migration that removes the
   one-template-per-(patient,finger) unique constraint.

7. **PAD / liveness.** Future work — no spoof-detection accuracy claims without attack data
   (no APCER/BPCER/ISO 30107-3 possible from bona-fide-only samples). Keep existing optical-flow /
   FFT-moiré liveness but reframe as "experimental," not "validated PAD." Server-side trust fix
   (geofence + WiFi decided server-side; client supplies evidence only) stays in scope as a
   security correctness item, independent of accuracy.

## Prior-work framing (for the report)
Finger-photo recognition is an established ~20-year field — contribution is the application
(mobile patient ID + geofenced access control), not the algorithm. Cite: ContactlessNet
(Tan & Kumar 2020), C2CL (Grosz et al. 2021, EER 0.30–1.20%), Fusion2Print (2026, EER 1.12%),
Malhotra et al. 2020 (EER 2.11–5.23%). Key honesty citation: NISTIR 8307 (2019) — single-finger
contactless 60–70% accuracy, four-finger 90–95%. Commercial: ONYX (Telos), Identy.io, VeriFinger.

## Status of code changes
- [x] #1 `--no-enhance` matcher-isolation bypass (image_processor.py + calibrate_far_frr.py) — applied, self-test PASS
- [x] #2 unify 3 thresholds to one config value (default 32.0) — applied, php -l + py_compile clean

## To-do
### Immediate (phase B — measurement)
- [x] Add `FINGERPRINT_MATCH_THRESHOLD=32.0` to live `laravel/.env` and `python-service/.env` (2026-06-17)
- [x] Verify harness self-test + real pipeline both modes (2026-06-17 — EER 0.04% self-test; 50 minutiae)
- [ ] Download SOCOFing — IN PROGRESS via Kaggle MCP (Lane 2); needs session restart to load MCP tools
- [ ] `python tools/calibrate_far_frr.py --data data/socofing --no-enhance --out reports/socofing_matcher`
- [ ] `python tools/calibrate_far_frr.py --data data/socofing --out reports/socofing_pipeline`
- [ ] Submit IIITD ISPFDv2 + RidgeBase access requests (start now — long lead time)
### Phase B — headline + calibration
- [ ] Contactless headline EER (ISPFDv2 → RidgeBase fallback)
- [ ] Set `FINGERPRINT_MATCH_THRESHOLD` from empirical FAR≤0.1% / EER operating point (both .env)
- [ ] 1:1 ROC/EER + simulated 1:N FAR-vs-N curve
### Conditional (only if contactless EER > ~10%)
- [ ] Multi-impression best-of-N (prove offline first) → schema migration if it helps
- [ ] Retune CLAHE/Gabor/threshold + minutiae quality filter, re-measure
- [ ] Last resort: pretrained CPU-friendly contactless extractor (no from-scratch training)
### Security / scope (independent of accuracy)
- [ ] Move liveness + geofence decision server-side
- [ ] Reframe liveness in docs as "experimental," add Scope / Limitations / Future Work sections

## Open questions to confirm
- N (enrolled patients/hospital) — assumed hundreds
- Latency pass/fail target — none set yet

> NOTE: The interview that produced this plan was run autonomously by a background agent that
> fabricated the user's answers. Treat every decision above as a PROPOSAL pending the user's
> real confirmation, not a settled agreement.
