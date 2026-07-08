# Plan 011: Shortlist 1:N hand identification via a FAISS index instead of scanning the full gallery

> **Executor instructions**: This is a larger design-sensitive change. Follow the
> plan, run every verification command, and keep the old path working until the
> new one has score parity. If anything in "STOP conditions" occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Http/Controllers/Api/VerificationController.php laravel/app/Services/FingerprintService.php python-service/app/routes/hand.py python-service/app/services/matcher.py python-service/app/services/faiss_service.py`
> If any changed, re-read the relevant "Current state" excerpts; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/001 (needs the FAISS + fusion tests for score-parity checks)
- **Category**: perf
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

1:N fingerprint/hand identification is a brute-force linear scan. For every
verification, Laravel pulls *every* active gallery-lead fingerprint for the
hospital, builds one candidate hand per patient, and POSTs the **entire** decrypted
gallery to the Python service, which loops over every candidate scoring 3–4 fingers
each. Latency and payload grow linearly with hospital patient count — the whole
encrypted gallery is decrypted, JSON-serialized, shipped over HTTP, and re-scored on
every single verification. The face path already solves exactly this shape with a
FAISS ANN index; the contactless fingerprint-embedding path should reuse that
infrastructure: enroll per-finger embedding vectors into a FAISS index and shortlist
before fusion, instead of scanning the full gallery.

**Important scoping note**: this optimization applies to the **embedding** path
(the learned contactless vectors that FAISS can index), NOT the minutiae placeholder
(minutiae templates aren't fixed-length vectors and don't fit FAISS). Confirm which
matcher is live before building; if the embedding matcher is the deciding one, this
is worth doing.

## Current state

`laravel/app/Http/Controllers/Api/VerificationController.php`, `loadCandidateHands()`
(around lines 528–552) pulls the full hospital gallery:
```php
private function loadCandidateHands(int $hospitalId): array
{
    $rows = Fingerprint::where('hospital_id', $hospitalId)
        ->where('is_active', true)
        ->where('is_gallery_lead', true)
        ->get(['id', 'patient_id', 'finger_position', 'template']);
    // groups all rows by patient, decrypts every template
    ...
}
```
`laravel/app/Services/FingerprintService.php`, `matchHand()` (around lines 357–372)
POSTs the whole candidate set in one request. `python-service/app/routes/hand.py`
`match_hand` (around lines 174–187) loops over every candidate; `matcher.py`
(around lines 200–208) fuses per finger.

The FAISS infrastructure to reuse: `python-service/app/services/faiss_service.py`
(`enroll`, `identify`, `remove_patient`, `rebuild`) — currently used only for face
(512-dim ArcFace vectors). Contactless finger embeddings are also fixed-length
vectors and can be indexed the same way (one vector per enrolled finger, tagged
with patient_id + finger_position).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Python tests | `cd python-service && python -m pytest -q` | all pass |
| Laravel tests | `cd laravel && composer test` | all pass |
| Filter | `cd laravel && php artisan test --filter "Hand\|Verify"` | pass |

## Scope

**In scope**:
- `python-service/app/services/faiss_service.py` — generalize to support a second
  index namespace for finger embeddings (or add a parallel `finger_index` module
  following the same pattern) — decide based on what you read; keep face untouched.
- `python-service/app/routes/hand.py` — add a shortlist step before full fusion.
- `laravel/app/Http/Controllers/Api/VerificationController.php` — enroll finger
  embeddings on hand enroll; call the shortlist path on verify.
- `laravel/app/Services/FingerprintService.php` — add the shortlist call.
- Tests in both services.

**Out of scope** (do NOT touch):
- The face FAISS index behavior (`identify` for faces) — reuse the *pattern*, don't
  change face scoring.
- The minutiae placeholder path — leave the O(N) scan for minutiae; it's the safe
  fallback and not FAISS-indexable.
- The fusion math itself — shortlist first, then fuse the shortlisted candidates
  with the *existing* fusion function so scores are identical to today for the
  candidates that survive the shortlist.

## Git workflow

- Branch: `advisor/011-faiss-shortlist-1n-hand`
- Commit per layer (index generalization, python route, laravel enroll, laravel
  verify, tests). Keep the old full-scan path callable behind a flag until parity
  is proven.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Confirm the embedding matcher is the deciding path

Read `VerificationController::verifyHand` and the matcher registry. If `verify/hand`
is still advisory-only on the minutiae placeholder (does not decide), STOP and
report — the shortlist has no value until the embedding matcher decides, and this
plan should wait behind that rollout.

**Verify**: you can state, from code, that the embedding matcher is registered and
deciding. If not → STOP.

### Step 2: Add a finger-embedding FAISS index

Following the exact pattern of the face index in `faiss_service.py`, provide an
index for per-finger contactless embeddings, keyed by `(patient_id, finger_position,
template_id)`. Reuse `_normalise`, `_save`, `_load_or_create` patterns; keep it in
a separate on-disk file from the face index. Include `enroll_finger`,
`identify_finger`, `remove_patient_fingers` equivalents. Apply the same
lock-snapshot discipline as plan 007 (if 007 landed, mirror it; if not, hold the
lock during identify).

**Verify**: `cd python-service && python -m pytest -q tests/test_faiss_roundtrip.py`
plus a new finger-index round-trip test → pass.

### Step 3: Shortlist before fusion in the hand route

In `hand.py` `match_hand`, when the request is embedding-domain, first query the
finger index with each probe finger to get a shortlist of candidate patients
(union of top-k per finger), then run the *existing* per-finger fusion only over
that shortlist. The response shape must be unchanged.

**Verify**: a python test asserts that for a gallery where only 1 of N patients is
near the probe, the shortlist contains that patient and the fused winner matches the
full-scan winner (score parity).

### Step 4: Enroll finger embeddings from Laravel on hand enroll

In the hand-enroll flow (`PatientController::enrollHand` → `FingerprintService`),
after storing the gallery-lead templates, also enroll each finger's embedding into
the new index (embedding-domain only). Mirror how face enroll calls
`enrollToIndex`. Ensure removal (`removeFingerprint`) also removes from the finger
index.

**Verify**: `cd laravel && php artisan test --filter Hand` → enroll/remove keep the
index in sync (mock the service calls as the existing tests do).

### Step 5: Use the shortlist on verify and prove parity

In `VerificationController::verifyHand`, call the shortlist path instead of
`loadCandidateHands()` shipping the whole gallery (embedding-domain only). Keep
`loadCandidateHands` as the minutiae fallback. Add a parity test: for a seeded
gallery, the fused match result (patient + decision) via the shortlist equals the
result via the old full-scan path.

**Verify**: `cd laravel && composer test` → green, including the parity test.

## Test plan

- Python: finger-index round-trip; shortlist-contains-true-match; fused winner
  parity vs full scan.
- Laravel: enroll/remove index sync; verify parity (shortlist result == full-scan
  result) on a seeded multi-patient gallery.
- Verification: both suites green.

## Done criteria

ALL must hold:

- [ ] `verify/hand` embedding path shortlists via FAISS; the full-gallery POST is no
      longer on the embedding hot path (minutiae fallback may still use it).
- [ ] Score/decision parity test passes (shortlist result == full-scan result).
- [ ] `cd python-service && python -m pytest -q` and `cd laravel && composer test` both exit 0.
- [ ] Face FAISS behavior unchanged (its tests still pass).
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 011 updated.

## STOP conditions

Stop and report back if:
- The embedding matcher is not yet the deciding path (Step 1 fails) — this plan
  waits.
- Contactless finger embeddings are not fixed-length vectors (can't be FAISS-
  indexed) — report; the approach doesn't apply.
- You cannot achieve score parity — do NOT ship a faster-but-different matcher;
  report the discrepancy.

## Maintenance notes

- Per-hospital index partitioning (also relevant to plan 005's cross-hospital
  masking) could be folded in here — consider tagging finger vectors with
  hospital_id and filtering at query time.
- This is a P3 scale optimization: at a pilot's patient count the linear scan is
  fine. Do not prioritize it over the P1/P2 correctness and security plans.
- Reviewer should scrutinize index/DB sync on enroll and remove, and confirm the
  minutiae fallback still works when the embedding matcher is absent.
