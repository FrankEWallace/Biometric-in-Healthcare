# Plan 005: Resolve identity nationally on both biometric paths; enforce access in one shared, audited authorization step

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Http/Controllers/Api/FaceController.php laravel/app/Http/Controllers/Api/VerificationController.php`
> If either changed, compare the "Current state" excerpts against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: none (this introduces the shared access-control seam plan 013 enriches)
- **Category**: bug / architecture
- **Planned at**: commit `a05e716`, 2026-07-08

## Why this matters

**Identity ≠ access.** The biometric engine's job is *"who is this person?"* —
answered nationally, against the whole gallery. Whether the operator may *see*
that person's records is a *separate* authorization decision. Today the code
conflates them: a correctly-identified patient from another hospital is reported
as **`no_match`**, so the system lies about identity to enforce an access rule.
The truth is "identity found; you are not authorized for this facility's record."

This plan makes identity resolution national on **both active identification
paths** — face verify and four-finger hand verify — and routes the hospital
boundary through **one shared, audited authorization step**
(`PatientAccessService::authorizePatientAccess(User $operator, Patient $patient)`).
Concretely it:

1. Fixes the face candidate-iteration bug (evaluate top-K in score order, not just
   `candidates[0]`).
2. Resolves identity **nationally** on both paths — the best match above threshold
   is the identified patient, regardless of hospital.
3. Enforces the hospital boundary as an access-control step **after**
   identification via the shared service: a cross-hospital hit returns
   **`access_restricted`** (identity resolved, records withheld) and writes an
   **audit** entry — never `no_match`.

**Why one shared service, both paths together (not "fingerprint later"):** shipping
face-national while hand stays hospital-scoped would give users *different answers
for the same person* across modalities — a governance defect. A single
`PatientAccessService` used by both controllers guarantees consistency and gives
plan 013 exactly one seam to grow (consent tuple, break-glass, referral policy,
insurer/regional access) without re-touching biometric code. When cross-hospital
referrals arrive, that is a *policy change in one service*, not a rewrite of two
controllers.

The FAISS face index is **already global across hospitals**, so face identifies
nationally for free. The hand path currently pre-filters candidates by hospital
(`loadCandidateHands`), so going national there means loading the full gallery and
applying the access check after the match (see the FAR note in "Interactions").

## Current state

### Face path — searches globally, then wrongly hides cross-hospital identity

`laravel/app/Http/Controllers/Api/FaceController.php`, `verify()`: requests 5
candidates (line ~252) but uses only `candidates[0]` (lines ~281–284), and
`interpretCandidate()` (lines ~440–449) returns `no_match` for a cross-hospital
candidate:
```php
$ft = FaceTemplate::with('patient:...')->find($candidate['template_id']);
if (! $ft || $ft->hospital_id !== $hospitalId || ! $ft->patient) {
    return ['no_match', null];          // ← identity WAS found; this hides it
}
$status = $score >= $threshold ? 'matched' : 'needs_review';
return [$status, $ft->patient];
```
Candidates are `['patient_id','template_id','score']`, sorted by score descending.

### Hand path — pre-filters candidates by hospital (never even finds cross-hospital)

`laravel/app/Http/Controllers/Api/VerificationController.php`:
- `verifyHand()` (lines ~394–520): builds a probe, loads candidates via
  `loadCandidateHands($hospital->id)`, calls `matchHand`, then applies the
  placeholder-safe decision (embedding decides at threshold 57.5; minutiae →
  `needs_review`). On a match it returns the patient directly.
- `loadCandidateHands(int $hospitalId)` (lines ~528–552):
  ```php
  $rows = Fingerprint::where('hospital_id', $hospitalId)   // ← hospital pre-filter
      ->where('is_active', true)
      ->where('is_gallery_lead', true)
      ->get(['id','patient_id','finger_position','template']);
  ```
  So the hand path only ever *searches* its own hospital — cross-hospital patients
  are invisible, which is a different failure shape than face but the same root
  (identity scoped by hospital).
- `verify()` (the DEPRECATED 1:N minutiae route, sunset headers per `routes/api.php`)
  is **out of scope** — do not modify it.

### Audit + access surfaces

`AuditLog::record(...)` and the controllers' `writeLog(...)` helpers already exist.
`laravel/app/Policies/` holds existing policies; `laravel/app/Services/` holds
domain services (where the new `PatientAccessService` belongs).

## The target decision state machine (identical for both paths)

For the best-scoring candidate above threshold:

| Condition | Status | Patient in client response | Audit |
|-----------|--------|----------------------------|-------|
| identified, access **allowed** | `matched` | full record | match |
| identified, access **denied** | `access_restricted` | **none — no PII** | denied entry **with** identified patient id |
| best score < threshold | `needs_review` | as today | review |
| no candidate | `no_match` | none | no-match |

Access is decided ONLY by `PatientAccessService::authorizePatientAccess($operator,
$patient)`. Today that returns `true` iff `$patient->hospital_id ===
$operator->hospital_id`; plan 013 changes the body, not the callers.

Privacy: on `access_restricted` the client gets no patient PII; the server audit
records the identified patient id + operator + hospital + outcome + timestamp.
(Governance decided 2026-07-10, ADR-013: `access_restricted` IS exposed to the
client — implement it exactly as this contract specifies.)

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Filter | `cd laravel && php artisan test --filter "FaceVerify\|HandVerify\|PatientAccess"` | pass |
| Audit actions | `grep -n "const ACTION_" laravel/app/Models/AuditLog.php` | lists constants |
| Flutter analyze | `cd mobile && flutter analyze` | no new errors |

## Scope

**In scope**:
- `laravel/app/Services/PatientAccessService.php` (create) — the shared
  `authorizePatientAccess(User $operator, Patient $patient): bool` (+ a reason).
- `laravel/app/Http/Controllers/Api/FaceController.php` — national top-K resolution
  + shared access step + `access_restricted` + audit.
- `laravel/app/Http/Controllers/Api/VerificationController.php` — `verifyHand`:
  national candidate loading + shared access step + `access_restricted` + audit.
- `laravel/app/Models/AuditLog.php` — add `ACTION_ACCESS_RESTRICTED` if none fits.
- `laravel/tests/Feature/` — `PatientAccessServiceTest.php`,
  `FaceVerifyAccessControlTest.php`, `HandVerifyAccessControlTest.php`.
- `mobile/` — face-verify and hand-verify result handlers learn `access_restricted`.

**Out of scope** (do NOT touch):
- The DEPRECATED `VerificationController::verify` (1:N minutiae) route — slated for
  removal; leave it. Document in the plan that only the two active paths are made
  consistent.
- `FaceService` / Python `/face/identify` FAISS query — already national.
- Removing `hospital_id` or the `hospital.access` middleware — the boundary is
  RELOCATED into `PatientAccessService`, not deleted.
- The FAISS-shortlist optimization for hand (that is plan 011) and the threshold
  values.
- The national-patient-ID migration, dedup/MPI, and consent engine (plan 013).

## Interactions & known costs (read before starting)

- **FAR / performance on the hand path**: making hand identification national means
  `loadCandidateHands` loads the whole gallery and `matchHand` scans it — an
  O(N_national) linear scan with no ANN shortlist yet. For a pilot-sized gallery
  this is acceptable; at national scale it needs plan 011 (FAISS shortlist) and the
  national-scale FAR posture in plan 013. **STOP** if the gallery is large enough
  that a full scan per verify is not viable (see STOP conditions) and coordinate
  with 011 first.
- **Consistency guarantee**: both active paths must ship together in this plan so
  they never diverge. Do not split face and hand into separate merges.

## Git workflow

- Branch: `advisor/005-national-identity-access-gate`
- Commit per unit (shared service; face; hand; Flutter; tests). All land together.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Build the shared authorization service

Create `laravel/app/Services/PatientAccessService.php` with
`authorizePatientAccess(User $operator, Patient $patient): bool` returning `true`
iff `$patient->hospital_id === $operator->hospital_id` today. Keep it a single,
well-named decision point with a short docblock stating this is the seam plan 013
enriches (consent/referral/break-glass). Consider returning a small result
object/enum if a reason string is useful for audit; a bool is acceptable for now.

**Verify**: `cd laravel && php artisan test --filter PatientAccessService` (after Step 6) → passes.

### Step 2: Face — resolve identity nationally across top-K

In `FaceController::verify`, replace the `candidates[0]`-only logic with a loop
selecting the **best candidate above threshold regardless of hospital**. Identity
interpretation must no longer reference `hospital_id`. Below-threshold best →
`needs_review`; empty → `no_match`.

**Verify**: `grep -n "candidates\[0\]" laravel/app/Http/Controllers/Api/FaceController.php` → none; `grep -n "hospital_id !== \$hospitalId\|hospital_id !== \$hospital" laravel/app/Http/Controllers/Api/FaceController.php` → not inside identity interpretation.

### Step 3: Face — apply the shared access step + audit

Once identified, call `PatientAccessService::authorizePatientAccess`. Allowed →
`matched` (full record). Denied → `access_restricted`, strip patient PII from the
client response, and write an audit entry (via `writeLog`/`AuditLog::record`,
`ACTION_ACCESS_RESTRICTED`) capturing operator id, operator hospital, identified
patient id, outcome=denied, timestamp.

**Verify**: `grep -n "access_restricted\|authorizePatientAccess" laravel/app/Http/Controllers/Api/FaceController.php` → present.

### Step 4: Hand — resolve identity nationally

In `VerificationController`, change `loadCandidateHands` to load the full gallery
(drop the `where('hospital_id', ...)` pre-filter) so `verifyHand` identifies
nationally. Keep the existing placeholder-safe decision (embedding decides at
threshold; minutiae → `needs_review`). Heed the FAR note in "Interactions".

**Verify**: `grep -n "where('hospital_id'" laravel/app/Http/Controllers/Api/VerificationController.php` → the hand-candidate loader no longer filters by hospital.

### Step 5: Hand — apply the SAME shared access step + audit

After a hand match resolves a patient, call the *same*
`PatientAccessService::authorizePatientAccess` and produce the identical
`matched` / `access_restricted` outcomes and audit as the face path. The two paths
must return the same status vocabulary for the same person.

**Verify**: `grep -n "access_restricted\|authorizePatientAccess" laravel/app/Http/Controllers/Api/VerificationController.php` → present in `verifyHand`.

### Step 6: Flutter — both verify screens learn `access_restricted`

Locate the handlers for the `/face/verify` and `/verify/hand` responses in
`mobile/lib` (face under `screens/face/` and/or `result_screen.dart`; hand under
`screens/verify/hand_verification_screen.dart`). Add an `access_restricted` branch
in BOTH: "Identity found — you are not authorized to view this patient's records at
this facility." Any unknown/unhandled status must degrade to no-access (never show
another hospital's PII).

**Verify**: `cd mobile && flutter analyze` → no new errors; `grep -rn "access_restricted" mobile/lib` → present in both flows.

### Step 7: Tests

- `PatientAccessServiceTest.php`: allow when same hospital, deny when different.
- `FaceVerifyAccessControlTest.php` and `HandVerifyAccessControlTest.php`
  (mock `FaceService::identify` / `FingerprintService::matchHand` as existing tests
  do), each covering the four decision-table rows, and specifically asserting:
  - a higher-scoring other-hospital candidate yields `access_restricted`, **not**
    `no_match`;
  - `access_restricted` responses carry **no** patient PII but DO write an audit
    entry containing the identified patient id;
  - face and hand return the **same** status for an equivalent cross-hospital hit
    (the consistency guarantee).

**Verify**: `cd laravel && php artisan test --filter "FaceVerifyAccessControl\|HandVerifyAccessControl\|PatientAccessService"` → all pass.

## Done criteria

ALL must hold:

- [ ] `grep -n "candidates\[0\]" laravel/app/Http/Controllers/Api/FaceController.php` → none.
- [ ] Identity resolution on both paths is hospital-agnostic; the only access
      decision is `PatientAccessService::authorizePatientAccess(User, Patient)`.
- [ ] Both active paths return `access_restricted` (not `no_match`) on a
      cross-hospital hit, with no client PII and a server audit containing the
      identified patient id.
- [ ] `loadCandidateHands` no longer pre-filters by hospital.
- [ ] Face and hand return the same status vocabulary for the same person (asserted by test).
- [ ] Flutter handles `access_restricted` in both flows; unknown statuses degrade to no-access.
- [ ] `cd laravel && composer test` exits 0; the three new test files pass.
- [ ] `hospital_id` + `hospital.access` middleware still exist (boundary relocated, not removed).
- [ ] The deprecated `VerificationController::verify` route is unchanged.
- [ ] `plans/README.md` status row for 005 updated.

## STOP conditions

Stop and report back if:
- ~~**Governance — client exposure of `access_restricted`**~~ **RESOLVED
  2026-07-10 (ADR-013 accepted)**: expose `access_restricted` to the client
  (zero PII, denial audit-logged with the resolved patient id). Do NOT suppress
  to `no_match`. This STOP condition no longer applies — implement
  `access_restricted` as specified in the response contract above.
- **FAR / scale on the hand path**: if the gallery is large enough that a full
  national linear scan per hand verify is not viable, STOP and coordinate with
  plan 011 (FAISS shortlist) before making hand identification national.
- `FaceService::identify` candidates are not sorted by score descending.
- Making hand national breaks the existing `HandVerify` tests in a way implying the
  candidate contract differs from the excerpt.

## Next architecture review — RESOLVED 2026-07-10 via ADR-013 (accepted)

1. **`access_restricted` client exposure vs. audit-only `no_match`** — DECIDED:
   expose `access_restricted` to the client. See
   `docs/adr/013-national-patient-identity.md` decision point 1.
2. **Patient↔hospital ownership model** — DECIDED: National Patient + Hospital
   Record (`patient_hospital_links` provenance table; authorization via
   `PatientAccessService`, not `hospital_id` equality). The migration is a future
   build plan; **this plan (005) still implements the seam with `hospital_id`
   equality inside the service body** — the decided model lands later without
   touching the biometric controllers. See ADR-013 decision point 2.

## Maintenance notes

- `PatientAccessService::authorizePatientAccess` is the single seam plan 013 grows
  into. Never let a hospital/authorization check leak back into identity resolution
  or into the two controllers' bodies — the rule lives in the service.
- Reviewer must confirm: identity resolves before access is checked; no
  cross-hospital PII reaches an unauthorized client; denials are audited with the
  identified patient id; face and hand are consistent.
- The deprecated 1:N minutiae `verify` remains hospital-scoped and is intentionally
  not aligned (it is being removed); only the two active paths are guaranteed
  consistent.
