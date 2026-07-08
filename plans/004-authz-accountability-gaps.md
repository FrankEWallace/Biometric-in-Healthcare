# Plan 004: Close authorization & accountability gaps (override self-approval, stage fail-open, missing audit logs)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise. When
> done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Http/Controllers/Api/SupervisorOverrideController.php laravel/app/Http/Controllers/Api/VisitStageController.php laravel/app/Http/Controllers/Api/UserController.php laravel/app/Http/Controllers/Api/HospitalController.php`
> If any in-scope file changed, compare the "Current state" excerpts against the
> live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

Three independent accountability gaps in a system whose entire premise is
on-premises biometric accountability:

1. **Supervisor override self-approval.** A supervisor override is the escape
   hatch that completes a visit stage *without* biometric verification (e.g.
   bandaged finger). `SupervisorOverrideController::resolve` lets `admin`, `doctor`,
   or `nurse` approve, and a `nurse` can also *create* the request — but nothing
   stops the same nurse from approving their own request. That collapses the
   two-person control into one: a nurse whose biometric fails can request an
   override and immediately self-approve, completing the stage with no biometric
   and no independent supervisor.
2. **Stage authorization fail-open.** `VisitStageController::verify` and
   `updateData` look up allowed roles as `STAGE_ROLES[$stageName] ?? []` and skip
   the role check when the list is empty. These routes carry no `role:` middleware,
   so an unmapped stage name means *any* authenticated same-hospital user may
   verify the stage or overwrite its EMR data. If `STAGE_ROLES` ever drifts from
   the persisted stage names, a restriction silently disappears.
3. **Missing audit entries on privileged mutations.** `UserController::update`
   changes `role`, `is_active`, and `hospital_id` (privilege escalation / account
   disable / tenant reassignment) with no `AuditLog` entry, while `store` and
   `destroy` log. `HospitalController::update` changes the geofence perimeter
   (`gps_*`, `gps_radius_meters`, `wifi_ssid`) with no audit entry, while `store`
   and `destroy` log.

## Current state

**1. Override self-approval** — `laravel/app/Http/Controllers/Api/SupervisorOverrideController.php`,
`resolve()` (around lines 123–168). It checks hospital scope and pending status,
then resolves. There is **no** check that the resolver differs from the requester:
```php
public function resolve(Request $request, SupervisorOverride $override): JsonResponse
{
    $user  = $request->user();
    $stage = $override->visitStage()->with('visit')->first();
    if ($stage->visit->hospital_id !== $user->hospital_id) {
        return response()->json(['error' => 'Not found.'], 404);
    }
    if (! $override->isPending()) {
        return response()->json(['error' => 'Override has already been resolved.'], 409);
    }
    // ← no check that $user->id !== $override->requested_by
    $data = $request->validate([...]);
    $override->resolve($user, $data['decision'], ...);
```
The route allows the same roles that can request: `routes/api.php`
`supervisor-overrides` → `resolve` has `role:admin,doctor,nurse`.

**2. Stage fail-open** — `laravel/app/Http/Controllers/Api/VisitStageController.php`,
around lines 94–96 (in `verify`) and 184–186 (in `updateData`):
```php
$allowedRoles = VisitStage::STAGE_ROLES[$stageName] ?? [];
if (! empty($allowedRoles) && ! in_array($user->role, $allowedRoles)) {
    return response()->json([...], 403);
}
```
When `$allowedRoles` is empty (stage name not in the map), the check is skipped.
`VisitStage::STAGE_ROLES` is defined at `laravel/app/Models/VisitStage.php:27`.

**3. Missing audit logs** — `UserController::update` (around lines 91–127) and
`HospitalController::update` (around lines 70–95) perform the mutations above with
no `AuditLog::record` call. The existing pattern to copy is in the same
controllers' `store`/`destroy`, e.g. `UserController.php:71`:
```php
AuditLog::record($request, AuditLog::ACTION_USER_CREATED, null, null, null, [
    'created_user_id' => $user->id, 'role' => $user->role, ...
]);
```
and `PatientController::update` uses a `fields_changed` payload pattern worth
matching. **Never** put raw biometric or credential values in the payload — field
keys and non-sensitive values only.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Filter | `cd laravel && php artisan test --filter "Override\|StageRole\|AuditOnUpdate"` | pass |
| Find AuditLog actions | `grep -n "const ACTION_" laravel/app/Models/AuditLog.php` | lists available action constants |

## Scope

**In scope**:
- `laravel/app/Http/Controllers/Api/SupervisorOverrideController.php` (resolve: add self-approval guard)
- `laravel/app/Http/Controllers/Api/VisitStageController.php` (verify + updateData: deny on unmapped stage)
- `laravel/app/Http/Controllers/Api/UserController.php` (update: add audit log)
- `laravel/app/Http/Controllers/Api/HospitalController.php` (update: add audit log)
- `laravel/app/Models/AuditLog.php` — only if a new `ACTION_*` constant is needed
- `laravel/tests/Feature/` — add `AccountabilityTest.php` (create)

**Out of scope** (do NOT touch):
- Route definitions in `routes/api.php` — the fixes are in-controller.
- `VisitStage::STAGE_ROLES` values — do not change which roles map to which stage;
  only change the *fail-open behavior* when a stage is absent.
- The override state machine (`SupervisorOverride::resolve`) — call it, don't rewrite.

## Git workflow

- Branch: `advisor/004-authz-accountability-gaps`
- One commit per gap + one for tests.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Forbid self-approval of supervisor overrides

In `resolve()`, after the pending check and before resolving, add:
```php
if ($override->requested_by === $user->id) {
    return response()->json([
        'error' => 'You cannot resolve an override you requested. A different supervisor must approve.',
        'code'  => 'self_approval_forbidden',
    ], 403);
}
```

**Verify**: `grep -n "self_approval_forbidden" laravel/app/Http/Controllers/Api/SupervisorOverrideController.php` → one match.

### Step 2: Make stage authorization deny-by-default

In both `verify` and `updateData`, treat a missing/empty `STAGE_ROLES` entry as
deny, not allow:
```php
$allowedRoles = VisitStage::STAGE_ROLES[$stageName] ?? null;
if ($allowedRoles === null || ! in_array($user->role, $allowedRoles, true)) {
    return response()->json([
        'error' => "Your role ({$user->role}) is not permitted at the {$stageName} stage.",
    ], 403);
}
```
This preserves behavior for every currently-mapped stage (all real stages are in
`STAGE_ROLES`) and closes the hole for any unmapped one.

**Verify**: `grep -n "?? \[\]" laravel/app/Http/Controllers/Api/VisitStageController.php` → no matches on the STAGE_ROLES lines.

### Step 3: Audit-log privileged user updates

In `UserController::update`, after the update succeeds, record an audit entry
listing only the changed field keys (compute the diff of `role`, `is_active`,
`hospital_id`). Reuse an existing `ACTION_*` constant if a suitable one exists
(check `grep -n "const ACTION_" laravel/app/Models/AuditLog.php`); if not, add
`ACTION_USER_UPDATED`. Example payload: `['updated_user_id' => $user->id,
'fields_changed' => ['role','is_active']]`. Do not log old/new credential values.

**Verify**: `grep -n "AuditLog::record" laravel/app/Http/Controllers/Api/UserController.php` → now appears in `update` too.

### Step 4: Audit-log hospital perimeter updates

In `HospitalController::update`, record an audit entry after a successful update,
listing changed perimeter field keys (`gps_latitude`, `gps_longitude`,
`gps_radius_meters`, `wifi_ssid`). Add `ACTION_HOSPITAL_UPDATED` / use existing
`'hospital_updated'` string style consistent with `store` (which uses the string
`'hospital_created'`).

**Verify**: `grep -n "AuditLog::record" laravel/app/Http/Controllers/Api/HospitalController.php` → now appears in `update` too.

### Step 5: Tests

Create `laravel/tests/Feature/AccountabilityTest.php`, patterned on the auth/role
setup in `AuthTest.php` / `PatientTest.php`. Cover:
- a nurse who created an override gets 403 (`self_approval_forbidden`) when
  resolving it; a *different* supervisor succeeds.
- a stage-verify request for an unmapped stage name is denied 403 (construct a
  stage whose name is not in `STAGE_ROLES`, or assert the guard denies when the
  role is not listed).
- `UserController::update` changing a role writes exactly one new `AuditLog` row;
  `HospitalController::update` changing the radius writes one.

**Verify**: `cd laravel && php artisan test --filter Accountability` → all pass.

## Test plan

- New file `laravel/tests/Feature/AccountabilityTest.php`, cases listed in Step 5.
- Pattern: `AuthTest.php` for role/user factories; assert `AuditLog::count()`
  deltas for the logging cases.
- Verification: `cd laravel && composer test` → green including new tests.

## Done criteria

ALL must hold:

- [ ] `grep -n "self_approval_forbidden" laravel/app/Http/Controllers/Api/SupervisorOverrideController.php` → one match.
- [ ] No `?? []` fail-open on the STAGE_ROLES lines in `VisitStageController.php`.
- [ ] `AuditLog::record` present in `update()` of both `UserController` and `HospitalController`.
- [ ] `cd laravel && composer test` exits 0; `AccountabilityTest` passes with the cases above.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 004 updated.

## STOP conditions

Stop and report back if:
- `SupervisorOverride` has no `requested_by` attribute matching the excerpt
  (schema drifted).
- Making stage auth deny-by-default breaks an existing passing test — that means a
  real stage is unmapped in `STAGE_ROLES`; report which one rather than adding it
  blindly.
- The audit-log helper signature differs from `AuditLog::record($request, $action, $patientId, ...)`.

## Maintenance notes

- Whenever a new visit stage is added, it MUST be added to `VisitStage::STAGE_ROLES`,
  or Step 2's deny-by-default will (correctly) block it — that is the intended
  fail-closed behavior.
- Reviewer should confirm no biometric/credential values leak into audit payloads.
- A fuller segregation-of-duties model (separate "supervisor" role) is deferred;
  the self-approval guard is the minimal correct fix for the pilot.
