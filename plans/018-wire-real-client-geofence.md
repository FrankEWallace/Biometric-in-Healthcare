# Plan 018: Wire the per-hospital client geofence; demote the 20 km anchor to a true fallback

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat d25ce31..HEAD -- mobile/lib/services/location_service.dart mobile/lib/screens/home_dashboard.dart mobile/lib/screens/shell/app_shell.dart mobile/lib/screens/dashboard/nurse_dashboard.dart mobile/lib/services/hospital_service.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. NOTE: the working tree at planning
> time already had uncommitted changes elsewhere in `mobile/` (iOS MediaPipe
> work) — those files are out of scope and must not be touched.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: MED
- **Depends on**: none
- **Category**: security / bug
- **Planned at**: commit `d25ce31`, 2026-07-11

## Why this matters

The client-side geofence is supposed to check the device against each
hospital's configured GPS circle (fetched from the API). In reality the
API-driven check `isWithinAnyHospital()` has **zero callers** — every gate
site calls the "fallback" `isWithinHospitalRange()`, which compares against
one hardcoded Dar es Salaam anchor with a **20 000 m radius** (widened from
500 m as a dev convenience and shipped). So the client geofence passes
anywhere within ~20 km of one fixed point, for every hospital. The server
still enforces its own geofence (`EnforceGeofence` middleware), so this is a
defence-in-depth failure, not a full bypass — but the client layer is
currently fiction, and its class doc claims behavior that doesn't exist.

## Current state

- `mobile/lib/services/location_service.dart` (94 lines, read it fully):
  - `:12-14` — fallback anchor: `_fallbackLat = -6.8235`, `_fallbackLng = 39.2695`,
    `_fallbackRadiusMeters = 20000.0`.
  - `:46-70` — `isWithinAnyHospital(List<Map<String, dynamic>> hospitals)` —
    correct per-hospital check (`gps_latitude`/`gps_longitude`/
    `gps_radius_meters`, default radius 200.0), `kDebugMode` bypass. **No callers.**
  - `:74-88` — `isWithinHospitalRange()` — single-anchor fallback. This is
    what all three gate sites call today.
- The three call sites (identical pattern — `Future.wait` with the wifi check):
  - `mobile/lib/screens/home_dashboard.dart:41` — `_locationService.isWithinHospitalRange(),`
  - `mobile/lib/screens/shell/app_shell.dart:64` — `_loc.isWithinHospitalRange(),`
  - `mobile/lib/screens/dashboard/nurse_dashboard.dart:37` — `_loc.isWithinHospitalRange(),`

  Example (home_dashboard.dart:35-50):
  ```dart
  final results = await Future.wait([
    _locationService.isWithinHospitalRange(),
    _networkService.isConnectedToHospitalWifi(),
  ]);
  ```
- `mobile/lib/services/hospital_service.dart:25-35` —
  `getHospitals({required String token})` already returns
  `List<Map<String, dynamic>>` from `GET /api/hospitals` (the exact shape
  `isWithinAnyHospital` documents); throws `HospitalException` on failure.
- Auth token is available at all three call sites' screens via
  `context.read<AuthProvider>().user?.token` (the app's standard pattern —
  see e.g. `mobile/lib/screens/verification_screen.dart` for usage).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `cd mobile && dart analyze` | 0 errors (9 pre-existing info lints OK) |
| Tests | `cd mobile && flutter test` | all pass |

## Scope

**In scope** (the only files you should modify):
- `mobile/lib/services/location_service.dart`
- `mobile/lib/screens/home_dashboard.dart`
- `mobile/lib/screens/shell/app_shell.dart`
- `mobile/lib/screens/dashboard/nurse_dashboard.dart`
- `plans/README.md` (status row)

**Out of scope** (do NOT touch):
- `mobile/lib/services/hospital_service.dart` — already correct.
- Server-side geofence (`laravel/app/Http/Middleware/EnforceGeofence.php`,
  `GeofenceService`) — the authoritative gate; unchanged.
- `mobile/lib/services/network_service.dart` (wifi SSID check).
- Any file under `mobile/ios/` or `mobile/lib/controllers/finger_guidance/`
  (in-flight uncommitted work belonging to someone else).
- The `kDebugMode => true` bypass — it is intentional for development.

## Git workflow

- Branch: `advisor/018-wire-real-client-geofence`
- Commit style: imperative subject + `(plan 018)` suffix.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add an orchestrating method to LocationService

In `location_service.dart`, add:

```dart
/// Preferred gate: fetch the hospital list and check the device against each
/// hospital's own GPS circle. Falls back to the single-anchor
/// [isWithinHospitalRange] ONLY when the list cannot be fetched.
Future<bool> isWithinConfiguredHospitals({
  required Future<List<Map<String, dynamic>>> Function() fetchHospitals,
}) async {
  if (kDebugMode) return true;
  List<Map<String, dynamic>> hospitals;
  try {
    hospitals = await fetchHospitals();
  } catch (_) {
    return isWithinHospitalRange(); // API unreachable — legacy fallback
  }
  if (hospitals.isEmpty) return isWithinHospitalRange();
  return isWithinAnyHospital(hospitals);
}
```

(The function-injection keeps `LocationService` free of an http/auth
dependency, matching its current dependency-free style.)

**Verify**: `cd mobile && dart analyze` → 0 errors.

### Step 2: Restore a sane fallback radius

Change `_fallbackRadiusMeters` from `20000.0` back to `500.0` in
`location_service.dart:14`. Update the class doc (`:4-9`) to describe the real
flow: orchestrator → per-hospital check → single-anchor fallback on fetch
failure only.

**Verify**: `grep -n "_fallbackRadiusMeters" mobile/lib/services/location_service.dart` → `= 500.0`.

### Step 3: Switch the three call sites

At each site, replace the `isWithinHospitalRange()` element of the
`Future.wait` list with:

```dart
_locationService.isWithinConfiguredHospitals(
  fetchHospitals: () => HospitalService()
      .getHospitals(token: context.read<AuthProvider>().user?.token ?? ''),
),
```

adding the needed imports (`hospital_service.dart`, `auth_provider.dart`,
`provider`) where missing. Capture the token BEFORE the `await` (read it into
a local variable at the top of `_runChecks`/`_check`) so no `context` use
crosses an async gap — match how the verify screens do it.

**Verify**: `grep -rn "isWithinHospitalRange()" mobile/lib/screens/` → no matches
(the method remains, called only from within `location_service.dart`); and
`cd mobile && dart analyze` → 0 errors.

### Step 4: Full check

**Verify**: `cd mobile && flutter test` → all pass (smoke test compiles the
whole tree, catching import/DI mistakes).

## Test plan

This repo has no Flutter unit-test infrastructure yet (plan 015, TODO), so no
new widget tests are required. Add one pure-Dart unit test that does not need
mocks: `mobile/test/location_service_test.dart` asserting
`isWithinConfiguredHospitals` (a) returns the fallback path result when
`fetchHospitals` throws, (b) uses the per-hospital list when it succeeds —
inject a `fetchHospitals` that returns a hospital at a known coordinate. If
`Geolocator` static calls make this untestable without mocks, note it in the
report and skip the test rather than pulling in a mocking framework (that is
plan 015's job).

## Done criteria

- [ ] `grep -rn "isWithinHospitalRange" mobile/lib/screens/` → no matches
- [ ] `grep -n "20000.0" mobile/lib/services/location_service.dart` → no matches
- [ ] `cd mobile && dart analyze` → 0 errors
- [ ] `cd mobile && flutter test` → all pass
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `GET /api/hospitals` turns out to be role-restricted such that nurses/clerks
  cannot call it (check `laravel/routes/api.php` if step 3's runtime behavior
  is in doubt) — the fix would then need a lighter public-shape endpoint,
  which is a scope change.
- The three call-site files have drifted from the excerpts (someone else is
  editing these screens).
- Adding the imports creates a provider/context pattern the screen doesn't
  already use — report rather than restructuring the screen.

## Maintenance notes

- If hospitals gain multiple geofence circles or SSIDs (plan 016 discussion),
  `isWithinAnyHospital` is the single place to extend.
- Reviewer: check the token is read before any `await` (no context-across-
  async-gap lint), and that the fallback path is reachable only on fetch
  failure.
- Deferred: caching the hospital list to avoid a fetch per gate check
  (fine at pilot scale; revisit with plan 011's perf work).
