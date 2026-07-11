# Plan 017: Calibrate and enable the contactless four-finger match threshold

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat d25ce31..HEAD -- laravel/config/services.php laravel/.env.example python-service/tools/ docs/calibration/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug (operational) — the core feature is disabled in production
- **Planned at**: commit `d25ce31`, 2026-07-11

## Why this matters

Every fingerprint verification flow (1:1 verify, 1:N identify, visit-stage
verify, multimodal confirm) routes through the four-finger contactless
embedding matcher, gated by `services.fingerprint.contactless_match_threshold`.
That config is **null by default and nothing sets it in any deployment**, so a
placeholder-safe gate forces every hand verification to `needs_review` —
staff must manually confirm every patient, and the system's core feature
never auto-decides. The embedding matcher (Ridgeformer ONNX) that the gate
was waiting for IS installed and wired; the calibration tooling exists in
`python-service/tools/`; prior eval runs exist in `docs/calibration/`. The
only missing step is a defensible threshold derived from THIS system's own
capture pipeline, and setting it.

## Current state

- `laravel/config/services.php:38-47` — the gate and its intent (read this
  comment in full; it is the contract this plan completes):

  ```php
  // hand score. Intentionally NULL by default: the minutiae matcher is
  // non-discriminative on finger photos (RidgeBase EER ~46%), so there is
  // no valid contactless operating point until a learned embedding matcher
  // is installed. While NULL, verify-hand returns advisory scores as
  // needs_review and NEVER auto-accepts — do not set this from minutiae
  // numbers. Calibrate with tools/ridgebase_eval.py once the embedding is
  // in place, then set FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD.
  'contactless_match_threshold' => env('FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD') !== null
      ? (float) env('FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD')
      : null,
  ```

- `laravel/.env.example:36` — `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=57.5`
  (a RidgeBase-derived example value, NOT validated on this app's captures).
- `python-service/tools/calibrate_far_frr.py` — FAR/FRR harness whose
  docstring says it runs `preprocess_fingerprint -> extract_template ->
  match_templates` over a labelled dataset (genuine vs impostor pairs from a
  `subject/finger_sample.jpg` layout) and reports EER + threshold-at-target-FAR.
  **Caution**: that pipeline description sounds like the single-finger path;
  `services.php` names `tools/ridgebase_eval.py` as the embedding calibrator.
- `python-service/tools/ridgebase_eval.py`, `python-service/tools/plot_calibration.py`
  — companion tools; prior outputs in `python-service/calibration_out/` and
  `docs/calibration/{ridgebase,socofing}/` (reports + eval logs).
- The consumers of the threshold (do NOT modify them; context only):
  `laravel/app/Http/Controllers/Api/VerificationController.php` (`verifyHand`,
  and `verifyMultimodal`'s placeholder-safe gate) and
  `laravel/app/Services/VisitService.php` (`tryHand`). All follow the pattern:
  auto-accept only when threshold is non-null AND the matcher name contains
  `embedding`.
- Docker: `docker-compose.yml` passes `./laravel/.env` via `env_file`, so
  production picks the threshold up from `laravel/.env`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Python deps | `cd python-service && source venv/bin/activate` (or `.venv`) | prompt shows venv |
| Python tests | `cd python-service && python -m pytest -q` | all pass (12+ passed) |
| Laravel tests | `cd laravel && php artisan test` | 132+ passed |
| Calibration tool help | `cd python-service && python tools/ridgebase_eval.py --help` | usage text, exit 0 |

## Scope

**In scope** (the only files you should modify/create):
- `python-service/tools/` — a new or extended script ONLY if step 2 shows no
  existing tool exercises the four-finger fused embedding path (prefer reuse).
- `docs/calibration/own-domain/` (create) — the new calibration report.
- `laravel/.env.example` — update the documented value + comment with the
  calibrated number and its provenance.
- `docs/deployment.mdx` — one paragraph: how/when to set the threshold.
- `plans/README.md` — status row.

**Out of scope** (do NOT touch):
- `laravel/config/services.php` and all threshold consumers — the gate logic
  is correct; only the env value changes.
- Any real `.env` file — never commit one; the operator sets production env.
- The ONNX model, matcher code, segmentation code.

## Git workflow

- Branch: `advisor/017-calibrate-contactless-threshold`
- Commit style (match `git log`): imperative subject + `(plan 017)` suffix.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Confirm the embedding matcher is what actually runs

Verify the Python service resolves the contactless domain to the embedding
matcher, not the minutiae placeholder:

**Verify**: `cd python-service && grep -n "embedding" app/services/matcher.py | head -10` →
shows domain routing to an Embedding matcher; and
`ls models/contactless_embedding.onnx` → file exists.

### Step 2: Identify the calibration tool that exercises the fused four-finger embedding path

Read `python-service/tools/ridgebase_eval.py` and
`python-service/tools/calibrate_far_frr.py` (docstrings + main()). Determine
which one scores pairs through the **embedding matcher** (and ideally the
four-finger fusion in `app/services/matcher.py`), as opposed to the
single-finger minutiae pipeline.

**Verify**: state in your report which tool + code path; if NEITHER tool
exercises the embedding matcher, STOP (see STOP conditions).

### Step 3: Assemble an own-domain labelled dataset

Collect finger captures taken with THIS app's capture pipeline (the
`FingerprintLivenessCameraScreen` four-finger photos, segmented by the
server). Minimum viable set: 10+ identities × 3+ captures each, in the
`subject/finger_sample.jpg` layout the tools document. Sources, in order of
preference: (a) an existing own-capture set if the operator has one (ask via
report if unclear), (b) captures produced during plan-001/002 testing if
retained, (c) a freshly collected set — if none exists, STOP and report that
data collection is the blocker (do not substitute RidgeBase/SOCOFing; the
whole point is own-domain data).

**Verify**: `find <dataset-dir> -name "*.jpg" | wc -l` → ≥ 30.

### Step 4: Run the calibration and record the report

Run the tool from step 2 over the dataset. Capture: EER, threshold at
FAR=1% and FAR=0.1%, and the genuine/impostor distributions plot
(`plot_calibration.py`). Write results to
`docs/calibration/own-domain/README.md` in the same format as
`docs/calibration/ridgebase/ridgeformer_eval.md`.

**Verify**: the README exists and contains a chosen threshold with its FAR/FRR
operating point stated.

### Step 5: Choose and document the operating point

Recommend the threshold at **FAR ≤ 1%** (hospital identification favors
false-reject-then-manual-review over false-accept). Update
`laravel/.env.example`: replace `57.5` with the calibrated value and extend the
comment: `# Calibrated <date> on own-domain set (N identities): FAR=x%, FRR=y% — see docs/calibration/own-domain/`.
Add a deployment paragraph to `docs/deployment.mdx`.

**Verify**: `grep -n "FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD" laravel/.env.example` → new value + provenance comment.

### Step 6: Prove the gate opens

With the threshold exported in the Laravel test env, run the existing suites
(they already set `config(['services.fingerprint.contactless_match_threshold' => 57.5])`
where needed, so no test edits should be required).

**Verify**: `cd laravel && php artisan test` → all pass; and
`cd python-service && python -m pytest -q` → all pass.

## Test plan

No new automated tests required — the gate's behavior at threshold is already
covered (`HandVerifyAccessControlTest`, `MultimodalVerifyTest`,
`VisitStageVerifyTest` all configure a threshold and assert accept/review
paths). The deliverable is the calibration report + documented value.

## Done criteria

- [ ] `docs/calibration/own-domain/README.md` exists with EER, FAR/FRR table,
      and a chosen threshold with rationale
- [ ] `laravel/.env.example` documents the calibrated value + provenance
- [ ] `docs/deployment.mdx` tells the operator to set the env var at deploy
- [ ] `cd laravel && php artisan test` exits 0
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Neither `ridgebase_eval.py` nor `calibrate_far_frr.py` exercises the
  embedding matcher — writing a new eval harness is a separate decision.
- No own-domain captures exist and none can be collected — report "blocked on
  data collection"; do NOT publish a RidgeBase-derived number as calibrated.
- The own-domain EER exceeds ~15% — the matcher may not be production-viable
  on real captures; that is a finding for the maintainer, not a threshold to
  ship.
- `laravel/config/services.php:38-47` no longer matches the excerpt above.

## Maintenance notes

- Re-run calibration whenever the capture pipeline changes (resolution,
  preprocessing, segmentation, model file) — the services.php comment already
  says the numbers track the algorithm.
- Reviewer should scrutinize: dataset provenance (own-domain only) and that no
  real `.env` was committed.
- Deferred: automating calibration in CI (needs a stored dataset; privacy
  question — biometric images in the repo are prohibited).
