# Plan 002: Make the four-finger embedding matcher the core of visit-stage verification

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report — do not
> improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Services/VisitService.php laravel/app/Http/Controllers/Api/VisitStageController.php laravel/app/Http/Controllers/Api/VerificationController.php mobile/lib/services/visit_service.dart mobile/lib/screens/visit/stage_verify_screen.dart`
> If any in-scope file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/001 (need a runnable way to prove the hand/embedding path)
- **Category**: bug / architecture
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

The visit-stage verification pipeline — the flow that verifies a patient at each
stage of a hospital visit — is both **broken** and **wired to the wrong matcher**.

**Broken**: three stacked defects in `laravel/app/Services/VisitService.php` make
it crash or silently no-match (see "The three crash bugs" below).

**Wrong matcher**: the stage pipeline's only fingerprint tier is *single-finger
minutiae* via the Python `/match` endpoint. But this project's calibrated core
biometric is the **four-finger contactless embedding** (Ridgeformer ONNX, fused
EER 8.85%, threshold 57.5). Minutiae on contactless finger photos is
non-discriminative (~coin-flip, EER 42–50%), so using it as the *primary* stage
matcher is a false-accept / wrong-patient safety risk. The embedding matcher is
already built and wired into the separate `/verify/hand` endpoint
(`VerificationController::verifyHand`) — but the visit-stage flow does not use it
at all.

This plan repoints the stage pipeline so the **four-finger embedding is the core
matcher** (decides at the calibrated threshold), **face is the fallback**, and
**single-finger minutiae is advisory-only** (reported but can never complete a
stage). It reuses the existing hand endpoints and the placeholder-safe decision
pattern already proven in `verifyHand`, and it fixes the three crash bugs along
the way.

## Current state

### The three crash bugs (in `VisitService.php`)

1. `tryFingerprint()` (around lines 233–258) filters templates on
   `template_format = 'sourceafis_v1'`, but stored templates are always tagged
   `minutiae_v1` — so the query never matches.
2. The same method calls `$this->fingerprint->verify(...)` — a method that no
   longer exists (renamed to `verifyAgainstAll()`), throwing an uncaught `\Error`
   (`catch (RuntimeException)` does not catch `\Error`).
3. `tryFace()` (around lines 260–288) calls `$faceTemplate->getEmbedding()`, which
   is undefined on `FaceTemplate` (only `getTemplate(): ?array` exists, returning
   `['embedding' => [...], ...]`). Same uncaught-`\Error` → HTTP 500.

### How the stage flow is shaped today

`laravel/app/Http/Controllers/Api/VisitStageController.php` `verify()` validates a
single fingerprint image (around lines 102–108):
```php
$data = $request->validate([
    'fingerprint_image' => 'required|string',
    'face_image'        => 'nullable|string',
    'gps_latitude'      => 'nullable|numeric',
    'gps_longitude'     => 'nullable|numeric',
    'wifi_ssid'         => 'nullable|string|max:100',
]);
...
$result = $this->visits->verifyStage(
    visit: $visit, stage: $stage, patient: $patient, hospital: $hospital,
    operatorId: $user->id,
    fingerprintImage: $data['fingerprint_image'],
    faceImage: $data['face_image'] ?? null,
    request: $request,
);
```
`VisitService::verifyStage` (line 146) then calls `tryFingerprint` (minutiae) then
`tryFace`. There is **no hand/embedding tier** anywhere in `VisitService`.

### The embedding path to reuse (already built)

`VerificationController::verifyHand` (lines 394–520) is the reference
implementation. Key pieces you will mirror:

- Segment + extract probe fingers:
  ```php
  $processed = $this->fingerprint->processHand($data['image'], $hand, 'contactless');
  $probe = [];
  foreach ($processed['fingers'] ?? [] as $finger) {
      $probe[$finger['finger_position']] = $finger['template'];
  }
  if (count($probe) < self::MIN_HAND_FINGERS) { /* 422 retake */ }
  ```
  `MIN_HAND_FINGERS = 3` (`VerificationController.php:24`).
- Fuse-match against candidate hands:
  ```php
  $result = $this->fingerprint->matchHand($probe, $candidates, 'contactless');
  // returns { patient_id, score, matcher, fingers_used, per_finger }
  ```
- **Placeholder-safe decision** (the exact gate to copy):
  ```php
  $threshold = config('services.fingerprint.contactless_match_threshold'); // 57.5 when set, null=advisory
  $usingPlaceholder = ! str_contains($matcherName, 'embedding');
  if ($threshold === null || $usingPlaceholder) { $status='needs_review'; $matched=false; }
  else { $matched = $matchedPatientId !== null && $fusedScore >= (float)$threshold; $status = $matched ? 'matched':'no_match'; }
  ```

Service signatures (`laravel/app/Services/FingerprintService.php`):
- `processHand(string $base64Image, string $hand='right', string $domain='contactless'): array` → `{ matcher, domain, fingers: [...] }`
- `matchHand(array $probe, array $candidates, string $domain='contactless'): array` where
  `$candidates = [['patient_id'=>int,'fingers'=>[finger_position=>template]], ...]`.

Candidate-hand loading pattern (from `VerificationController::loadCandidateHands`,
around lines 528–552) — you will adapt it to a **single** patient:
```php
$rows = Fingerprint::where('patient_id', $patient->id)
    ->where('is_active', true)
    ->where('is_gallery_lead', true)
    ->get(['id','patient_id','finger_position','template']);
// group by finger_position, decode getTemplate(), require >= MIN_HAND_FINGERS
```

### Flutter side

`mobile/lib/services/visit_service.dart` `verifyStage()` (lines 167–205) currently
sends `fingerprint_image`. Its only caller is
`mobile/lib/screens/visit/stage_verify_screen.dart`. The four-finger capture that
already exists is `mobile/lib/screens/verify/hand_verification_screen.dart` +
`FingerprintService.verifyHand()` in `mobile/lib/services/fingerprint_service.dart`
— use those as the pattern for capturing a hand photo and posting `image` + `hand`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Single test | `cd laravel && php artisan test --filter VisitStage` | pass |
| Python tests | `cd python-service && python -m pytest -q` | pass (from plan 001) |
| Flutter analyze | `cd mobile && flutter analyze` | no new errors |
| Flutter tests | `cd mobile && flutter test` | pass |
| Grep dead methods | `grep -rn "getEmbedding\|->fingerprint->verify(\|sourceafis_v1" laravel/app` | no matches after fix |

## Scope

**In scope**:
- `laravel/app/Services/VisitService.php` — add a `tryHand()` embedding tier +
  `loadPatientHand()` helper; make `tryFingerprint()` advisory-only; fix the 3 bugs.
- `laravel/app/Http/Controllers/Api/VisitStageController.php` — accept `hand_image`
  (+ `hand` side) in the contract; pass it through to `verifyStage`.
- `laravel/tests/Feature/VisitStageVerifyTest.php` (create).
- `mobile/lib/services/visit_service.dart` — `verifyStage` sends `hand_image`/`hand`.
- `mobile/lib/screens/visit/stage_verify_screen.dart` — capture a hand photo.
- `mobile/test/` — a widget/logic test for the changed screen if feasible.

**Out of scope** (do NOT touch):
- `VerificationController::verifyHand` and `loadCandidateHands` — read them as the
  pattern; do not change them.
- `FingerprintService` / `FaceService` method signatures — call existing methods.
- The Python service (`processHand`/`matchHand`/`/match-hand`) — no changes.
- The `contactless_match_threshold` value (57.5) — reuse, don't retune.
- `PatientController::enrollHand` — enrollment already stores 4 gallery-lead
  templates per patient; do not change it.
- 1:N identification — the stage flow is **1:1** (the visit's patient is known);
  do not turn it into a hospital-wide search.

## Git workflow

- Branch: `advisor/002-stage-embedding-core`
- Commit per logical unit (bug fixes, hand tier, contract, Flutter, tests).
- Do NOT push or open a PR unless instructed.

## Steps

### Step 0: Verify the biometric threshold configuration (before touching code)

The entire hand tier is gated on `services.fingerprint.contactless_match_threshold`.
It is currently set only in the local `laravel/.env`
(`FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=57.5`) — **not** in `.env.example` and
not in `phpunit.xml`. On a fresh deploy or CI env built from `.env.example`, the
threshold resolves to `null`, the placeholder-safe gate degrades every hand
result to `needs_review`, and the system can never auto-verify a patient — an
operational outage that looks healthy.

1. Confirm `php artisan tinker --execute="var_dump(config('services.fingerprint.contactless_match_threshold'));"`
   prints `float(57.5)` locally.
2. Add `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=57.5` to `laravel/.env.example`
   (with a comment that null = advisory mode, no auto-verify).
3. In the new test class (Step 6), set
   `config(['services.fingerprint.contactless_match_threshold' => 57.5])` in
   `setUp()` so tests never depend on the host env.

Note: do NOT make the app hard-fail when the threshold is null — `null=advisory`
is a designed pre-calibration mode in `verifyHand`. A loud boot-time warning for
an unset threshold belongs in plan 009 (deploy/config hardening), not here.

**Verify**: `grep -n "FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD" laravel/.env.example` → present.

### Step 1: Fix the three crash bugs so the fallback tiers don't 500

- In `tryFingerprint()`: change the filter from `'sourceafis_v1'` to `'minutiae_v1'`
  (or drop the format filter), replace `$this->fingerprint->verify(...)` with
  `verifyAgainstAll($tmpPath, [['fingerprint_id'=>$fp->id,'template'=>$fp->getTemplate()]])`
  reading `['verdict','score']`, and broaden the catch to `\Throwable`.
- In `tryFace()`: replace `$faceTemplate->getEmbedding()` with
  `$faceTemplate->getTemplate()['embedding']` guarded for null, and broaden its
  catch to `\Throwable`.

**Verify**: `grep -rn "getEmbedding\|->fingerprint->verify(\|sourceafis_v1" laravel/app/Services/VisitService.php` → no matches.

### Step 2: Add the four-finger embedding tier (`tryHand`) as the primary matcher

Add a private helper and a tier method to `VisitService`. `tryHand(Patient $patient,
string $handImage, string $hand): array` must:
1. `loadPatientHand($patient)` — the single-patient adaptation of
   `loadCandidateHands` (gallery-lead templates keyed by finger_position; return
   `null` if fewer than `MIN_HAND_FINGERS` = 3 are enrolled).
2. `processHand($handImage, $hand, 'contactless')` → build `$probe`
   `[finger_position => template]`; if `< MIN_HAND_FINGERS` usable → return
   `['matched'=>false,'score'=>0.0,'status'=>'needs_review','reason'=>'too_few_fingers']`.
3. `matchHand($probe, [$patientHand], 'contactless')` → fused score + matcher name.
4. Apply the **exact placeholder-safe gate** from `verifyHand` (copy it): matched
   only when the matcher name contains `'embedding'` AND the threshold is set AND
   `fusedScore >= threshold`. Otherwise `needs_review`, `matched=false`.

Define `MIN_HAND_FINGERS = 3` as a `VisitService` constant (mirror
`VerificationController`). Wrap external calls in `try/catch (\Throwable)` →
degrade to `needs_review`, never 500.

**Verify**: `grep -n "function tryHand\|MIN_HAND_FINGERS\|str_contains(\$matcher" laravel/app/Services/VisitService.php` → present.

### Step 3: Rewire `verifyStage` tier order — embedding → face → minutiae(advisory)

Change `verifyStage`'s signature/body so it accepts a `handImage` (+ `hand` side)
and runs tiers in this order:
1. `tryHand()` — if `matched`, complete the stage with modality `hand`.
2. `tryFace()` — if `matched`, complete with modality `face`.
3. `tryFingerprint()` — **advisory only**: run it if a legacy single-finger contact
   image is supplied, include its score in the response, but it must **never** set
   `matched=true` or complete the stage. If neither hand nor face matched, return
   `fallback_exhausted` so the client offers a supervisor override.

Keep the response keys the controller already reads (`matched`, `modality`,
`score`, `verification_log_id`, `fallback_exhausted`). Do not complete a stage on
a `needs_review` result.

**Verify**: reading `verifyStage`, the only paths that set `matched=true` are the
hand and face tiers; `tryFingerprint` cannot complete a stage.

### Step 4: Update the Laravel stage contract

In `VisitStageController::verify`, accept the hand photo:
```php
$data = $request->validate([
    'hand_image'        => 'required|string',
    'hand'              => 'nullable|in:left,right',
    'face_image'        => 'nullable|string',
    'gps_latitude'      => 'nullable|numeric',
    'gps_longitude'     => 'nullable|numeric',
    'wifi_ssid'         => 'nullable|string|max:100',
    'fingerprint_image' => 'nullable|string', // legacy single-finger, advisory only
]);
```
Pass `handImage`, `hand` (default `'right'`), `faceImage`, and the optional legacy
`fingerprintImage` into `verifyStage`. Keep the audit-log call; add `hand` to its
payload where relevant.

**Verify**: `grep -n "hand_image" laravel/app/Http/Controllers/Api/VisitStageController.php` → present; `cd laravel && php artisan test --filter VisitStage` → passes after Step 6.

### Step 5: Update the Flutter stage-verify flow to capture a hand photo

- In `mobile/lib/services/visit_service.dart`, change `verifyStage` to send
  `hand_image` + `hand` (keep `face_image`/GPS/SSID) instead of `fingerprint_image`.
  Mirror the JSON body and 90s timeout used by `FingerprintService.verifyHand`.
- In `mobile/lib/screens/visit/stage_verify_screen.dart`, replace single-finger
  capture with the hand-photo capture used by
  `mobile/lib/screens/verify/hand_verification_screen.dart` (camera → base64 hand
  image → `verifyStage`). Reuse the right/left hand toggle and the "retake / too
  few fingers" error handling already in that screen.

**Verify**: `cd mobile && flutter analyze` → no new errors; `grep -n "hand_image" mobile/lib/services/visit_service.dart` → present; `grep -n "fingerprint_image" mobile/lib/services/visit_service.dart` → gone (or only a legacy optional).

### Step 6: Tests

Create `laravel/tests/Feature/VisitStageVerifyTest.php`, modeled on the
service-mock setup in `MultimodalVerifyTest.php` (mock `FingerprintService` and
`FaceService`). Cover:
- **hand embedding matches** (mock `matchHand` → high fused score, matcher name
  contains `'embedding'`, threshold configured) → stage completes, modality `hand`,
  one verification log.
- **hand needs_review, face matches** → stage completes via face (the path that
  used to 500).
- **placeholder matcher** (mock `matchHand` → matcher name `minutiae-...`) →
  `needs_review`, stage NOT completed, even if the score is high (proves minutiae
  can't auto-accept).
- **all fail** → `fallback_exhausted`, 422, no 500, no completion.
- **patient-ID mismatch despite high score** — mock `matchHand` → `['patient_id' => <some other id>, 'score' => 95, 'matcher' => 'ridgeformer_embedding']` while the visit belongs to a different patient → `matched=false`, stage NOT completed. Today the candidate list contains only the visit's patient so this can't fire, but that invariant lives solely in the candidate list; plans 005/011 push the hand matcher toward 1:N, and this test is the regression tripwire that keeps stage verification 1:1.

Set `config(['services.fingerprint.contactless_match_threshold' => 57.5])` in
`setUp()` (see Step 0) so all five cases are env-independent.

Add a Flutter widget/logic test for the changed screen if the existing test
infrastructure allows (otherwise note it as deferred).

**Verify**: `cd laravel && php artisan test --filter VisitStageVerify` → all pass.

## Test plan

- Laravel: the five cases in Step 6, asserting modality, `matched`, that a
  non-embedding matcher never completes a stage, and that a returned patient ID
  differing from the visit's patient never completes a stage.
- Pattern: `MultimodalVerifyTest.php`.
- Verification: `cd laravel && composer test` → green; `cd mobile && flutter analyze && flutter test` → green.

## Done criteria

ALL must hold:

- [ ] `grep -rn "getEmbedding\|->fingerprint->verify(\|sourceafis_v1" laravel/app/Services/VisitService.php` → nothing.
- [ ] `VisitService` has a `tryHand` tier using `processHand`/`matchHand` and the
      embedding placeholder-safe gate; `tryFingerprint` can never set `matched=true`.
- [ ] `VisitStageController::verify` accepts `hand_image`; a placeholder (non-embedding)
      matcher yields `needs_review` and does not complete a stage (asserted by test).
- [ ] Flutter `verifyStage` sends `hand_image`; the stage screen captures a hand photo;
      `flutter analyze` clean.
- [ ] `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=57.5` present in `laravel/.env.example`,
      and `VisitStageVerifyTest` overrides the threshold via `config()` in `setUp()`
      (no dependency on the host env).
- [ ] `cd laravel && composer test` exits 0 with `VisitStageVerifyTest` (5 cases,
      including the patient-ID-mismatch guard) passing.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 002 updated.

## STOP conditions

Stop and report back (do not improvise) if:
- `services.fingerprint.contactless_match_threshold` is null in the test/dev env —
  then the embedding tier will (correctly) return `needs_review` and no test can
  assert a `matched` hand result. Set it in the test (config override) to 57.5;
  if you cannot, report that the threshold is unset rather than lowering the gate.
- `matchHand`/`processHand` return shapes differ from the excerpts (contract drift).
- The stage flow turns out to have consumers other than `stage_verify_screen.dart`
  that still send `fingerprint_image` — report them before removing the field.
- Capturing a hand photo in the stage screen requires camera/permission plumbing
  not already present in `hand_verification_screen.dart` — report; don't hand-roll
  a second camera stack.

## Maintenance notes

- The stage pipeline now shares the embedding decision logic with `verifyHand`.
  If that gate changes (e.g. threshold source, matcher-name check), keep the two
  in sync — consider extracting the placeholder-safe decision into a shared method
  in a follow-up so it lives in one place.
- Minutiae remains only as an advisory signal here; if a genuine *contact* sensor
  path is ever added, revisit whether it should be allowed to decide for contact
  prints (where minutiae is accurate).
- **Known policy inconsistency (intentionally out of scope)**: the standalone
  multimodal endpoint `VerificationController::verify` (POST `/verify`, and its
  mobile caller `face_service.dart`) still allows single-finger contactless
  minutiae to make an identity decision — the same modality this plan demotes to
  advisory for visit stages. Plan 002 deliberately does not touch it; it should
  be reviewed separately for consistency with the contactless fingerprint policy.
- Face fallback runs at `FaceService::MATCH_THRESHOLD = 0.75` cosine — a strict
  operating point for InsightFace (typical deployments use 0.40–0.55), so its
  realistic failure mode is false-reject → supervisor override, not a soft
  backdoor. But unlike the hand threshold (57.5, calibrated, EER 8.85%), 0.75 is
  hardcoded and has no calibration study on this population. Documentation
  (plan 010) should state explicitly: hand is the primary biometric; face is a
  fallback with a separately configured, uncalibrated threshold.
- Plan 008 hardens stage completion against concurrent double-verify — it touches
  `logAndCompleteStage` in the same file; sequence 002 before 008 if both run.
- Reviewer should confirm no tier except hand-embedding and face can complete a
  stage, and that a low/absent-model result degrades to supervisor-override, not a
  silent pass.
