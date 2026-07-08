# Plan 006: Make face enrollment transaction-safe and FAISS-consistent

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Http/Controllers/Api/FaceController.php laravel/app/Services/FaceService.php`
> If either changed, compare the "Current state" excerpts against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (but coordinate with 005/007 — same file/subsystem)
- **Category**: bug
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

`FaceController::enroll` has two related consistency defects:

1. **Check-then-act race on the template cap.** The active-template collection
   (and its count) is read *before* the `DB::transaction()` opens, and the cap
   comparison uses that stale count inside the transaction with no row lock. Two
   concurrent enrolls for the same patient can both read `count < MAX` and both
   insert, exceeding the per-patient cap.
2. **External FAISS mutations inside the DB transaction are not rolled back.**
   FAISS is an external HTTP service, not part of the DB transaction. The code
   calls `removeFromIndex` and `enrollToIndex` *inside* `DB::transaction()`. If a
   later call throws and rolls back the DB, the FAISS index has already been
   mutated and is **not** reverted — leaving the DB and the index divergent (e.g.
   a patient's vectors dropped from the index while their templates remain active
   in the DB). That degrades future identification for that patient.

The fix: lock the patient's templates inside the transaction so the cap check is
atomic, and move FAISS synchronization to *after* the DB commits so a rollback
cannot desync the index.

## Current state

`laravel/app/Http/Controllers/Api/FaceController.php`, `enroll()`:

Stale read before the transaction (around lines 98–101):
```php
$activeTemplates = FaceTemplate::where('patient_id', $patient->id)
    ->where('is_active', true)
    ->orderBy('created_at')
    ->get();

DB::transaction(function () use ($patient, $request, $result, $qualityScore, $activeTemplates) {
    // 1. Persist the new template first...
    $ft = new FaceTemplate(); ...; $ft->save();

    // 2. Enforce per-patient template cap — evict oldest if needed.
    if ($activeTemplates->count() >= FaceService::MAX_TEMPLATES_PER_PATIENT) {
        $oldest = $activeTemplates->first();
        $oldest->update(['is_active' => false]);
        try {
            $this->face->removeFromIndex($patient->id);           // ← external, inside txn
            $activeTemplates->skip(1)->each(function ($survivor) use ($patient) {
                ...
                $this->face->enrollToIndex($patient->id, $survivor->id, $decoded['embedding']); // ← external
            });
        } catch (\RuntimeException $e) { throw $e; }               // ← rolls back DB, not FAISS
    }

    // 3. Register the new template in FAISS.
    try {
        $this->face->enrollToIndex($patient->id, $ft->id, $result['embedding']);  // ← external, inside txn
    } catch (\RuntimeException $e) { throw $e; }
    ...
});
```
`FaceService` methods available: `enrollToIndex(int $patientId, int $templateId,
array $embedding)`, `removeFromIndex(int $patientId)`, `rebuildIndex(...)`. There
is a `activeTemplatePayload()` helper on the controller used for full rebuilds.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Filter | `cd laravel && php artisan test --filter "Enroll\|FaceEnroll"` | pass |

## Scope

**In scope**:
- `laravel/app/Http/Controllers/Api/FaceController.php` (`enroll()` only)
- `laravel/tests/Feature/EnrollmentTest.php` or a new `FaceEnrollConsistencyTest.php`

**Out of scope** (do NOT touch):
- `FaceService` method signatures.
- The Python FAISS service.
- `FaceController::verify` (that's plans 005/007).
- `MAX_TEMPLATES_PER_PATIENT` value.

## Git workflow

- Branch: `advisor/006-face-enroll-transaction-faiss-consistency`
- One commit for the locking/reorder change, one for tests.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Move the cap read inside the transaction with a lock

Inside `DB::transaction()`, before inserting the new template, re-read the active
templates with a pessimistic lock so concurrent enrolls serialize:
```php
$activeTemplates = FaceTemplate::where('patient_id', $patient->id)
    ->where('is_active', true)
    ->orderBy('created_at')
    ->lockForUpdate()
    ->get();
```
Remove the earlier pre-transaction read. The cap comparison now uses this locked,
current collection.

**Verify**: `grep -n "lockForUpdate" laravel/app/Http/Controllers/Api/FaceController.php` → present in `enroll`.

### Step 2: Defer all FAISS mutations until after commit

Restructure so the transaction does DB work only (insert new template, deactivate
oldest if over cap) and records what FAISS changes are needed. After
`DB::transaction()` returns successfully, perform the FAISS sync. Two acceptable
implementations — pick one and keep it simple:

- **(Preferred) Rebuild-from-DB after commit**: after the transaction commits,
  call the existing full/patient rebuild path from the now-authoritative DB rows
  (e.g. `removeFromIndex($patient->id)` then `enrollToIndex` for each surviving
  active template, or reuse `rebuildIndex($this->activeTemplatePayload())` if a
  per-patient variant isn't available). Because this reads committed DB state, the
  index converges to match the DB even if a prior attempt half-failed.
- **(Alternative) Post-commit incremental**: collect the exact enroll/remove calls
  during the transaction, then execute them after commit; on FAISS failure, log a
  reconcilable warning (the DB is already correct; the index can be rebuilt via the
  existing self-heal path in `verify`).

Whichever you choose, if the post-commit FAISS sync throws, the DB must remain
committed and correct, and the failure must be logged (not swallowed) so the
divergence is visible and recoverable.

**Verify**: no `$this->face->enrollToIndex` / `removeFromIndex` call remains inside
the `DB::transaction()` closure — `grep -n "face->enrollToIndex\|face->removeFromIndex" laravel/app/Http/Controllers/Api/FaceController.php`
and confirm by reading that all matches are after the transaction block.

### Step 3: Tests

In a feature test (extend `EnrollmentTest.php` or add `FaceEnrollConsistencyTest.php`,
patterned on the service-mock setup there):
- Enroll up to the cap, then one more → oldest becomes inactive, active count never
  exceeds `MAX_TEMPLATES_PER_PATIENT`.
- Mock `FaceService::enrollToIndex` to throw on the *post-commit* call → assert the
  DB template row is still persisted (committed) and a warning is logged, i.e. the
  DB is not rolled back by a FAISS failure. This is the behavior change: previously
  a FAISS failure discarded the DB write.

**Verify**: `cd laravel && php artisan test --filter "Enroll"` → all pass.

## Test plan

- Cases in Step 3. Assert `FaceTemplate::where('patient_id',$p)->where('is_active',true)->count()`
  stays `<= MAX_TEMPLATES_PER_PATIENT`, and that a post-commit FAISS throw leaves
  the new row committed.
- Pattern: `EnrollmentTest.php`.
- Verification: `cd laravel && composer test` → green.

## Done criteria

ALL must hold:

- [ ] `lockForUpdate` used for the cap read inside the transaction.
- [ ] No FAISS (`enrollToIndex`/`removeFromIndex`) calls inside the `DB::transaction()` closure.
- [ ] `cd laravel && composer test` exits 0; new consistency tests pass.
- [ ] A post-commit FAISS failure does not roll back the DB template insert (asserted by test).
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 006 updated.

## STOP conditions

Stop and report back if:
- There is no per-patient way to re-sync FAISS (no `removeFromIndex` + re-enroll
  and no patient-scoped rebuild) — then document the limitation and use the
  existing `verify` self-heal rebuild as the recovery path, but still move the
  calls post-commit.
- Moving FAISS post-commit breaks an existing test that asserted rollback-on-FAISS-
  failure — that test encodes the *old* (buggy) contract; update it to the new
  contract and note the change.

## Maintenance notes

- The system now tolerates transient index/DB divergence and self-heals on next
  `verify` (the rebuild-when-empty path). A reviewer should confirm the post-commit
  failure is logged loudly enough to catch in monitoring.
- Plan 007 fixes a *separate* FAISS race inside the Python service; this plan is
  about the Laravel enroll transaction boundary. They don't conflict.
