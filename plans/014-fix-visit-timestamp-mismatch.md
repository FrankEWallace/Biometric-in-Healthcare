# Plan 014: Fix the Visit model/migration timestamp mismatch

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report — do not
> improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ee972d4..HEAD -- laravel/app/Models/Visit.php laravel/database/migrations/2026_05_17_000004_create_visits_table.php laravel/app/Services/VisitService.php laravel/app/Http/Controllers/Api/VisitController.php`
> If any in-scope file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P0 (production-breaking, discovered live)
- **Effort**: S
- **Risk**: LOW (single-model fix, narrow blast radius)
- **Depends on**: — (independent; discovered while implementing plan 002, unrelated to its scope)
- **Category**: bug
- **Planned at**: commit `ee972d4`, 2026-07-08

## Why this matters

`POST /api/visits` (`VisitController::store` → `VisitService::openVisit` →
`Visit::create()`) is the entry point for the entire patient-visit workflow —
it is how a clerk checks a patient in. It is currently **broken in every
environment**, including the live dev database (not just sqlite tests):

```
SQLSTATE[42S22]: Column not found: 1054 Unknown column 'updated_at' in
'field list' (... insert into `visits` (..., `updated_at`, `created_at`)
values (...))
```

Reproduced directly against the dev MySQL database on 2026-07-08 via
`Visit::create([...])` — see verification command below. This means no new
visit can be opened right now, regardless of how correct the biometric
verification logic (plan 002) is — the workflow never gets that far.

This was latent because **no test exercises `VisitController::store` or
`VisitService::openVisit`** (confirmed: `find tests -iname "*Visit*"` returns
only `VisitStageVerifyTest.php`, which builds its `Visit` fixture via the
query builder specifically to route around this bug — see that file's
`setUp()` comment).

## Current state

### The mismatch

`laravel/database/migrations/2026_05_17_000004_create_visits_table.php`
creates the `visits` table with `opened_at`/`closed_at` timestamp columns but
**no** `created_at`/`updated_at` (no `$table->timestamps()` call). Confirmed
live: `Schema::getColumnListing('visits')` returns exactly `id, hospital_id,
patient_id, opened_by, closed_by, visit_type, status, opened_at, closed_at,
reopen_count, reopen_reason` — no `created_at`/`updated_at`.

`laravel/app/Models/Visit.php` does not set `public $timestamps = false;` (nor
does any trait), so Eloquent's default `$timestamps = true` applies and every
`Visit::create()` / `->save()` on a new instance appends `created_at` and
`updated_at` to the insert — columns that don't exist.

By contrast, `visit_stages` **does** have `created_at`/`updated_at`
(`Schema::getColumnListing('visit_stages')` includes both), and `VisitStage`
correctly relies on default Eloquent timestamps. Only `Visit` is affected.

### Why Option B (disable timestamps), not Option A (add the columns)

Investigated before writing this plan, not left to the executor to guess:

- `Visit` already has purpose-built chronology columns: `opened_at` (set via
  `useCurrent()` at the DB level) and `closed_at`. `VisitController::index`
  sorts and filters on `opened_at` (`orderByDesc('opened_at')`,
  `whereDate('opened_at', ...)`) — never on `created_at`.
- No code anywhere — grepped across `laravel/app` and `mobile/lib` — reads
  `$visit->created_at`, `visit.created_at`, or `visit.createdAt`.
- There is no `VisitFactory`, so no test scaffolding assumes timestamp columns
  exist either.
- Adding `created_at`/`updated_at` would be pure schema growth with no
  consumer — two redundant columns duplicating what `opened_at` already means
  for a `Visit` (a visit's "creation" *is* its opening).

If a future audit trail needs a true `updated_at` (e.g. to see when a visit
row was last touched, distinct from `opened_at`/`closed_at`), that is a
separate, deliberate feature — not a fix for this bug. Do not add it here.

## Scope

**In scope**:
- `laravel/app/Models/Visit.php` — add `public $timestamps = false;`.
- `laravel/tests/Feature/VisitControllerTest.php` (create) — smoke-test
  `POST /api/visits`, `PUT /api/visits/{visit}/close`,
  `PUT /api/visits/{visit}/reopen` actually work end-to-end.
- `laravel/tests/Feature/VisitStageVerifyTest.php` — replace the
  `DB::table('visits')->insertGetId(...)` workaround in `setUp()` with plain
  `Visit::create(...)` now that it works, and delete the comment explaining
  the workaround (no longer needed).

**Out of scope** (do NOT touch):
- The `visits` table migration — no new migration needed under Option B.
- `VisitStage` — unaffected; already has real timestamps.
- Plan 002's biometric logic — already shipped and unrelated to this bug.

## Git workflow

- Branch: `advisor/014-fix-visit-timestamps`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Reproduce, then fix

Reproduce first so you're fixing a confirmed failure, not a hypothetical:

```
php artisan tinker --execute="
  \$h = App\Models\Hospital::factory()->create();
  \$p = App\Models\Patient::factory()->create(['hospital_id' => \$h->id]);
  \$u = App\Models\User::factory()->create(['hospital_id' => \$h->id]);
  App\Models\Visit::create(['hospital_id'=>\$h->id,'patient_id'=>\$p->id,'opened_by'=>\$u->id,'visit_type'=>'pending','status'=>'open','opened_at'=>now()]);
"
```
Expected (before fix): `QueryException ... Unknown column 'updated_at'`.
**Clean up the fixture rows this creates afterward** (`Hospital::delete()`
cascades to the patient/user) — don't leave repro data in the dev database.

Then add to `Visit.php`:
```php
class Visit extends Model
{
    public $timestamps = false;

    protected $fillable = [
```

**Verify**: re-run the tinker snippet above → prints the new visit's ID with
no exception. Clean up the fixture rows again.

### Step 2: Add a regression test for the visit lifecycle

Create `laravel/tests/Feature/VisitControllerTest.php` covering, at minimum:
- `POST /api/visits` with a valid patient + verification log → 201, visit
  created, `clerk_checkin` stage completed (mirrors `openVisit`'s contract).
- `PUT /api/visits/{visit}/close` → 200, visit closed.
- `PUT /api/visits/{visit}/reopen` → 200, visit reopened, `clerk_checkout`
  reset to pending.

Use `RefreshDatabase` and real `Visit::create()` calls (no more query-builder
workaround) — this test exists specifically to catch a regression of this bug.

**Verify**: `cd laravel && php artisan test --filter VisitControllerTest` → all pass.

### Step 3: Remove the workaround in VisitStageVerifyTest

In `laravel/tests/Feature/VisitStageVerifyTest.php::setUp()`, replace:
```php
$visitId = DB::table('visits')->insertGetId([...]);
$this->visit = Visit::find($visitId);
```
with:
```php
$this->visit = Visit::create([...]);
```
Remove the explanatory comment above it (the bug it documents is now fixed)
and the now-unused `use Illuminate\Support\Facades\DB;` import if nothing else
in the file needs it.

**Verify**: `cd laravel && php artisan test --filter VisitStageVerify` → all 5 cases still pass.

## Test plan

- `VisitControllerTest` (Step 2): the three lifecycle assertions above.
- `VisitStageVerifyTest`: unchanged behavior, now via the real `Visit::create()` path.
- Full suite: `cd laravel && composer test` → green, count should be 106 + however
  many `VisitControllerTest` cases you add (not fewer).

## Done criteria

ALL must hold:

- [ ] `Visit::$timestamps = false` is set.
- [ ] The tinker reproduction in Step 1 succeeds with no exception, against
      both sqlite (test) and the real dev MySQL connection.
- [ ] `VisitControllerTest` exists and passes, covering open/close/reopen.
- [ ] `VisitStageVerifyTest` no longer uses the `DB::table('visits')` workaround.
- [ ] `cd laravel && composer test` exits 0.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 014 updated.

## STOP conditions

Stop and report back (do not improvise) if:
- Any code is found (after a repo-wide grep, not just the files checked while
  writing this plan) that reads `$visit->created_at` / `$visit->updated_at` —
  Option A (add the migration columns) becomes correct instead of Option B,
  and the fix shape changes.
- The reproduction in Step 1 does NOT fail on the current codebase — the bug
  may have already been fixed or the schema may differ from what's documented
  here; re-verify before proceeding.

## Maintenance notes

- This bug has been live since the `visits` table migration was written
  (2026-05-17) with no `VisitController`/`openVisit` test coverage catching
  it — a gap plan 001's CI baseline should prevent from recurring for other
  untested lifecycle endpoints.
- Checked 2026-07-08 whether this is a systemic pattern: swept
  `patients`, `hospitals`, `fingerprints`, `face_templates`,
  `verification_logs`, `supervisor_overrides`, `users`, `visit_stages` for the
  same migration/model timestamp mismatch — all have `created_at`. `visits` is
  an isolated case, not a pattern; no broader audit needed.
