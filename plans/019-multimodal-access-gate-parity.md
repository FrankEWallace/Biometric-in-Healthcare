# Plan 019: Bring the multimodal verify path under the ADR-013 national-identity access gate

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat d25ce31..HEAD -- laravel/app/Http/Controllers/Api/VerificationController.php laravel/tests/Feature/MultimodalVerifyTest.php mobile/lib/services/face_service.dart mobile/lib/screens/verify/multimodal_verification_screen.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security (access-control consistency / decision drift)
- **Planned at**: commit `d25ce31`, 2026-07-11

## Why this matters

ADR-013 (`docs/adr/013-national-patient-identity.md`, **Accepted**, both
decision points signed off 2026-07-10) decides: identity is resolved
**nationally**; the hospital boundary is enforced afterward by
`PatientAccessService`; a cross-hospital hit returns `access_restricted`
(identity found, records withheld), **never a fake `no_match`**. Plan 005
implemented this for the face and four-finger hand paths. The **multimodal**
path (`POST /api/verify/multimodal` — face shortlist → hand confirm) was never
covered: its `buildShortlist()` silently drops other hospitals' face
templates, so a cross-hospital patient gets `no_match` with no
`access_restricted` signal and no audit of the identified patient. One of four
verification paths contradicts the accepted architecture — the exact
divergence-between-paths plan 005's shared service was created to prevent.

## Current state

All in `laravel/app/Http/Controllers/Api/VerificationController.php` unless
noted. Line numbers are from commit `d25ce31`.

- `verifyMultimodal` (`:236-397`): validates, geofences, runs face liveness +
  FAISS identify, then:
  - `:288` — `$shortlist = $this->buildShortlist($faissResult['candidates'] ?? [], $hospital->id);`
  - `buildShortlist` (`:780-805`) drops foreign templates:
    ```php
    if (! $ft || ! $ft->is_active || $ft->hospital_id !== $hospitalId || ! $ft->patient) {
        return null;
    }
    ```
  - Decision block (`:345-355`): `matched` → patient from shortlist;
    otherwise `needs_review` with `shortlist->first()['patient']`. **No
    `PatientAccessService` call anywhere in this method.**
- The pattern to mirror — `verifyHand` (`:499-556`):
  ```php
  $identifiedPatient = $matched && $matchedPatientId
      ? \App\Models\Patient::find($matchedPatientId)
      : null;
  $accessRestricted = $identifiedPatient !== null
      && ! $this->access->authorizePatientAccess($operator, $identifiedPatient);
  if ($accessRestricted) {
      $status = 'access_restricted';
  }
  // Client never receives cross-hospital PII; the server-side log/audit
  // keeps the identified patient id for accountability.
  $responsePatient = $accessRestricted ? null : $identifiedPatient;
  ```
  plus audit action `AuditLog::ACTION_ACCESS_RESTRICTED` and response field
  `'candidate_patient_id' => $accessRestricted ? null : $matchedPatientId`.
- `PatientAccessService` is already injected as `$this->access` (`:39`).
- Old-behavior test that must FLIP:
  `laravel/tests/Feature/MultimodalVerifyTest.php:280`
  (`candidates_from_other_hospitals_are_excluded_from_the_shortlist`) —
  currently asserts a foreign-hospital FAISS hit yields `no_match`. Under
  ADR-013 it must yield `access_restricted` with `patient = null`.
- Mobile: `mobile/lib/services/face_service.dart:98-124` —
  `MultimodalVerifyResult` has only matched/needs_review getters (the
  single-face `FaceVerifyResult` at `:57-69` already has
  `isAccessRestricted`). The screen
  `mobile/lib/screens/verify/multimodal_verification_screen.dart` has no
  access_restricted branch. The dialog pattern to copy exists at
  `mobile/lib/screens/verify/hand_verification_screen.dart:203-226`
  (`_showAccessRestrictedDialog` — lock icon, no PII, FilledButton OK).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && php artisan test` | all pass |
| One suite | `cd laravel && php artisan test --filter=MultimodalVerifyTest` | all pass |
| Analyze | `cd mobile && dart analyze` | 0 errors |
| Flutter test | `cd mobile && flutter test` | all pass |

## Scope

**In scope** (the only files you should modify):
- `laravel/app/Http/Controllers/Api/VerificationController.php` —
  `verifyMultimodal` and `buildShortlist` only
- `laravel/tests/Feature/MultimodalVerifyTest.php`
- `mobile/lib/services/face_service.dart` — `MultimodalVerifyResult` only
- `mobile/lib/screens/verify/multimodal_verification_screen.dart`
- `plans/README.md` (status row)

**Out of scope** (do NOT touch):
- `verifyHand`, `verify`, `verifyFace` methods and their tests — already
  correct; they are your reference, not your patch surface.
- `PatientAccessService` — the rule lives there and does not change.
- `loadShortlistHands` — already keyed by patient id with no hospital filter.
- FAISS/face service code, `FaceController`.

## Git workflow

- Branch: `advisor/019-multimodal-access-gate-parity`
- Commit style: imperative subject + `(plan 019)` suffix.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make buildShortlist national

Remove the hospital filter from `buildShortlist` (`:791`): drop the
`$ft->hospital_id !== $hospitalId` clause (keep `!$ft`, `!is_active`,
`!patient`). Remove the now-unused `$hospitalId` parameter and update the one
call site (`:288`). Update the docblock: shortlist is national; the hospital
boundary is applied AFTER identification via `PatientAccessService`, matching
`loadCandidateHands` (`:565-575` docblock says exactly this — copy its
wording).

**Verify**: `cd laravel && php artisan test --filter=MultimodalVerifyTest` →
the `candidates_from_other_hospitals...` test now FAILS (expected — it pins
the old behavior; you flip it in step 3). All other cases pass.

### Step 2: Apply the access gate after the decision

In `verifyMultimodal`'s decision block, after `$matched`/`$patient`/`$status`
are set, mirror the `verifyHand` pattern exactly (excerpt above):

- Determine `$identifiedPatient` — the decided patient (matched patient, or on
  `needs_review` the top face candidate that would be shown to staff).
- `$accessRestricted = $identifiedPatient !== null && ! $this->access->authorizePatientAccess($operator, $identifiedPatient);`
- When restricted: `$status = 'access_restricted'`, response `patient => null`,
  no `ehr`/`insurance` lookups, and the `writeLog` row still records
  `$identifiedPatient->id` (accountability keeps the id server-side).
- Audit: use `AuditLog::ACTION_ACCESS_RESTRICTED` when restricted (see
  `verifyHand:529-531` for the ternary pattern).

**Verify**: `cd laravel && php artisan test` → only the pinned old-behavior
multimodal test fails.

### Step 3: Flip the old-behavior test and add coverage

Rewrite `candidates_from_other_hospitals_are_excluded_from_the_shortlist` as
`cross_hospital_identity_returns_access_restricted_without_pii`: foreign
FAISS hit + passing hand confirm → assert `status == 'access_restricted'`,
`patient == null`, no `ehr` in response, and a `verification_logs` row exists
with the identified patient id and status `access_restricted` (model on
`HandVerifyAccessControlTest` — read it first, it asserts exactly this
contract for the hand path). Also add: same-hospital match still returns
`matched` with patient (should already pass).

**Verify**: `cd laravel && php artisan test` → ALL pass.

### Step 4: Mobile — surface the status

In `face_service.dart`, add to `MultimodalVerifyResult`:
`bool get isAccessRestricted => status == 'access_restricted';` and update the
status doc comment. In `multimodal_verification_screen.dart`, add an
`isAccessRestricted` branch to the result handling that shows the same dialog
as `hand_verification_screen.dart:203-226` (copy the `_showAccessRestrictedDialog`
widget verbatim — plan 012/DEBT-03 will consolidate duplicates later; match
the existing pattern, do not invent a shared widget here).

**Verify**: `cd mobile && dart analyze` → 0 errors; `flutter test` → pass.

## Test plan

- Flip + add in `MultimodalVerifyTest.php` (step 3): restricted case,
  same-hospital happy path. Pattern source: `HandVerifyAccessControlTest.php`.
- No new Flutter tests (no infra — plan 015); `flutter test` smoke must pass.

## Done criteria

- [ ] `grep -n "hospital_id !== " laravel/app/Http/Controllers/Api/VerificationController.php` → no match inside `buildShortlist`
- [ ] `grep -n "authorizePatientAccess" laravel/app/Http/Controllers/Api/VerificationController.php` → present in BOTH `verifyHand` and `verifyMultimodal`
- [ ] `cd laravel && php artisan test` exits 0, including the flipped test
- [ ] `grep -n "isAccessRestricted" mobile/lib/services/face_service.dart` → present on `MultimodalVerifyResult`
- [ ] `cd mobile && dart analyze` → 0 errors; `cd mobile && flutter test` → pass
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `verifyMultimodal` or `buildShortlist` no longer matches the excerpts
  (drift — the method was edited 2026-07-11; more edits may follow).
- The `needs_review` + access-gate interaction is ambiguous in a way this plan
  doesn't settle: if the TOP face candidate is cross-hospital but a LOWER
  same-hospital candidate exists, this plan says gate the top candidate
  (restricted) — if implementing that breaks an existing test other than the
  pinned one, stop and report rather than choosing a different policy.
- You find yourself wanting to modify `PatientAccessService` — that means the
  seam doesn't fit and the design needs review.

## Maintenance notes

- ADR-013 phase 2 (consent/referral/break-glass) will extend
  `PatientAccessService::authorizePatientAccess`; this path inherits it
  automatically once gated — that is the point of the shared seam.
- Reviewer: confirm no PII fields reach the response on `access_restricted`
  (the shortlist eager-loads `full_name,date_of_birth,nida,gender,phone`).
- Deferred: consolidating the four `_showAccessRestrictedDialog` copies
  (tracked in plan 012's scope refresh).
