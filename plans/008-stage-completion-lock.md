# Plan 008: Lock visit-stage completion against concurrent double-verify

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Http/Controllers/Api/VisitStageController.php laravel/app/Services/VisitService.php`
> If either changed, compare the "Current state" excerpts against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (but touches the same file as plan 002 — sequence after 002 if both are run)
- **Category**: bug
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

Stage verification has a check-then-act with no locking: `VisitStageController::verify`
checks `$stage->isCompleted()` and returns 409 if done, but the actual completion
write happens later in `VisitService::logAndCompleteStage` in a separate
transaction. Nothing locks the stage row between the check and the write. Two
concurrent verify requests for the same stage (a double-tap, a client retry) can
both pass the `isCompleted()` gate, both create `VerificationLog` rows, and both
mark the stage completed — producing duplicate verification/audit logs and a
last-writer-wins `verification_log_id`. That undermines the one-verification-per-
stage integrity the visit state machine assumes, and pollutes the audit trail the
system exists to keep clean.

## Current state

`laravel/app/Http/Controllers/Api/VisitStageController.php` (around lines 85–92):
```php
if ($stage->isCompleted()) {
    return response()->json([
        'error'      => 'This stage has already been verified.',
        'verified_at' => $stage->verified_at,
    ], 409);
}
```

`laravel/app/Services/VisitService.php`, `logAndCompleteStage()` (around lines
290–328) opens its own `DB::transaction(...)` and updates the stage to completed —
but does not re-check completion under a lock:
```php
private function logAndCompleteStage(Visit $visit, VisitStage $stage, ...): VerificationLog
{
    return DB::transaction(function () use (...) {
        // creates VerificationLog and updates $stage to completed
        ...
    });
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Filter | `cd laravel && php artisan test --filter VisitStage` | pass |

## Scope

**In scope**:
- `laravel/app/Services/VisitService.php` (`logAndCompleteStage` — add lock + re-check)
- `laravel/tests/Feature/` — add a test asserting single completion under repeat calls

**Out of scope** (do NOT touch):
- The `isCompleted()` early gate in the controller — leave it (fast-path 409); the
  authoritative guard is the locked re-check.
- The biometric matching logic (plan 002).
- Route/middleware definitions.

## Git workflow

- Branch: `advisor/008-stage-completion-lock`
- One commit for the lock, one for the test.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Re-check completion under a row lock inside the completing transaction

At the top of the `DB::transaction` closure in `logAndCompleteStage`, re-load the
stage `lockForUpdate()` and abort if it is already completed, so the check and the
write are atomic:
```php
return DB::transaction(function () use (...) {
    $locked = VisitStage::whereKey($stage->id)->lockForUpdate()->first();
    if ($locked->isCompleted()) {
        // Another concurrent request already completed this stage.
        throw new StageAlreadyCompletedException($locked); // or return a sentinel the caller maps to 409
    }
    // ... existing VerificationLog creation + stage update, operating on $locked ...
});
```
Decide the abort mechanism that fits the existing control flow: either a dedicated
exception caught by the controller and mapped to HTTP 409, or a return sentinel the
caller checks. Match how the codebase already signals such conditions (grep for
existing custom exceptions under `laravel/app/Exceptions`; if none fit, a small
`RuntimeException` subclass mapped in the controller is fine). Ensure the duplicate
request produces **no** second `VerificationLog` row and returns 409.

**Verify**: `grep -n "lockForUpdate" laravel/app/Services/VisitService.php` → present in `logAndCompleteStage`.

### Step 2: Test single-completion under repeated calls

Add a feature test (patterned on the existing visit-stage tests / `MultimodalVerifyTest.php`
mock setup) that:
- completes a stage once → 200/expected success, exactly one `VerificationLog` row
  for that stage.
- issues a second verify for the same, now-completed stage → 409, and the
  `VerificationLog` count for that stage is still exactly one.

(A true concurrent double-write is hard to force deterministically in a feature
test; asserting the second sequential call is rejected and no duplicate log is
written validates the locked re-check, which is the mechanism that also closes the
concurrent window.)

**Verify**: `cd laravel && php artisan test --filter VisitStage` → passes.

## Test plan

- Cases in Step 2, asserting `VerificationLog::where('visit_stage_id',$id)->count() === 1`
  after a duplicate attempt.
- Pattern: existing visit-stage feature tests.
- Verification: `cd laravel && composer test` → green.

## Done criteria

ALL must hold:

- [ ] `logAndCompleteStage` re-loads the stage with `lockForUpdate()` and re-checks
      completion inside its transaction.
- [ ] A second verify on a completed stage returns 409 and writes no second
      `VerificationLog` (asserted by test).
- [ ] `cd laravel && composer test` exits 0.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 008 updated.

## STOP conditions

Stop and report back if:
- `logAndCompleteStage` is not the sole completion writer (grep for other places
  that set a stage `status` to `completed`, e.g. the supervisor-override approval
  path in `SupervisorOverrideController::resolve`) — those need the same guard;
  report the list before broadening scope.
- The DB driver in tests is SQLite and does not honor `lockForUpdate` — the logical
  re-check still prevents the sequential duplicate; note that true row locking is
  only exercised under MySQL (the production driver per `docker-compose.yml`).

## Maintenance notes

- The supervisor-override approval path also completes a stage without biometric
  (`SupervisorOverrideController::resolve`, plan 004 touches it) — if double-resolve
  is a concern there too, apply the same lock pattern in a follow-up.
- Reviewer should confirm the 409 response shape matches the controller's existing
  early-gate 409 so clients handle both identically.
