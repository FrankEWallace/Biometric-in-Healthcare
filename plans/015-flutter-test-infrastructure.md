# Plan 015: Establish Flutter test infrastructure

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report — do not
> improvise. When done, update the status row for this plan in `plans/README.md`.

## Status

- **Priority**: P3 (quality/DX, not blocking functionality)
- **Effort**: M
- **Risk**: LOW (additive — new dev dependencies and test files only)
- **Depends on**: — (independent)
- **Category**: test-coverage / DX
- **Planned at**: commit `ee972d4`, 2026-07-08

## Why this matters

The Flutter app (`mobile/`) has exactly one test:
`mobile/test/widget_test.dart`, the default template smoke test. There is:
- no `mockito`/`mocktail` dependency,
- no camera-service abstraction/fake for screens that require `CameraScreen`,
- no pattern for injecting a fake `AuthProvider`, `LocationService`,
  `NetworkService`, or the HTTP-backed `*Service` classes into a widget test.

This surfaced concretely while implementing plan 002: the plan asked for "a
Flutter widget/logic test for the changed screen if the existing test
infrastructure allows" — and it doesn't. Every screen in `mobile/lib/screens`
that captures a photo, calls a service, or reads a provider is currently
untestable without hand-rolling scaffolding per-screen, which produces
inconsistent, throwaway test setups instead of a reusable pattern.

This plan builds that pattern once so future UI plans (including a
follow-up widget test for `stage_verify_screen.dart`, deferred by plan 002)
can require a real test instead of deferring again.

## Current state

- `mobile/pubspec.yaml` `dev_dependencies` — only `flutter_test` (SDK) and
  `flutter_lints`. No `mocktail` or `mockito`.
- Services that need faking for screen tests: `LocationService`,
  `NetworkService` (`mobile/lib/services/`), and the HTTP-backed services
  (`VisitService`, `FingerprintService`, `FaceService`) — none define an
  interface/abstract class, so they can't be swapped for a fake without
  either refactoring to an interface or using `mocktail`'s class mocking
  (which works on concrete classes without an interface).
- `CameraScreen` (`mobile/lib/screens/camera_screen.dart`) and the
  liveness-camera screens directly use the `camera` plugin, which needs a
  platform channel mock in tests (`camera` package ships
  `camera_platform_interface` test helpers for this).
- `AuthProvider` (`mobile/lib/providers/auth_provider.dart`) is consumed via
  `context.read<AuthProvider>()` — needs a `ChangeNotifierProvider` wrapper
  with a fake user/token in `pumpWidget`.

## Scope

**In scope**:
- `mobile/pubspec.yaml` — add `mocktail` to `dev_dependencies`.
- `mobile/test/support/` (new directory) — shared test helpers:
  - `fake_auth_provider.dart` — a `AuthProvider` preloaded with a fake
    logged-in user/token.
  - `mock_services.dart` — `mocktail` `Mock` classes for `VisitService`,
    `FingerprintService`, `FaceService`, `LocationService`, `NetworkService`.
  - `pump_app.dart` — a `pumpApp(tester, widget, {providers})` helper wrapping
    `MaterialApp` + `MultiProvider` + the app's theme, so screen tests don't
    each hand-roll boilerplate.
- `mobile/test/screens/hand_verification_screen_test.dart` (new) — one
  worked example: pump the screen, mock `FingerprintService.verifyHand`,
  assert the matched/needs_review/no_match UI branches render.
- `mobile/test/screens/stage_verify_screen_test.dart` (new) — the test
  plan 002 deferred: mock `VisitService.verifyStage`, assert the hand →
  face → override phase transitions and the "Attempt N of 3" counter.

**Out of scope** (do NOT touch):
- Refactoring `VisitService`/`FingerprintService`/`FaceService` into
  interfaces — `mocktail` mocks concrete classes directly; do this only if a
  STOP condition below says it's unavoidable.
- Golden-image tests — not requested; skip unless a future plan asks for them.
- Any screen not listed above — this plan proves the pattern with two
  screens; a broader test-coverage push is a separate future plan.

## Git workflow

- Branch: `advisor/015-flutter-test-infra`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add mocktail and confirm it resolves

```
cd mobile && flutter pub add --dev mocktail
```

**Verify**: `mobile/pubspec.yaml` has `mocktail: ^<version>` under
`dev_dependencies`; `flutter pub get` exits 0.

### Step 2: Build the shared test helpers

Create `mobile/test/support/fake_auth_provider.dart`,
`mobile/test/support/mock_services.dart`, and
`mobile/test/support/pump_app.dart` per the Scope description. Keep each
mock a thin `mocktail` `Mock` subclass — no behavior beyond what `mocktail`
provides; stub method returns per-test with `when(...).thenAnswer(...)`.

**Verify**: `cd mobile && flutter analyze` → no new errors in `test/support/`.

### Step 3: Worked example — `HandVerificationScreen`

Write `mobile/test/screens/hand_verification_screen_test.dart` using the
helpers from Step 2. Cover at minimum:
- Captured image + `verifyHand` mocked to return a match → navigates to
  `EhrScreen` (assert via `find.byType(EhrScreen)` after `pumpAndSettle`).
- `verifyHand` mocked to return `needs_review` → the advisory dialog appears
  (`find.text('Manual Review Required')`).
- `verifyHand` throws `FingerprintException(kind: qualityTooLow)` → the
  mapped error message renders.

**Verify**: `cd mobile && flutter test test/screens/hand_verification_screen_test.dart` → all pass.

### Step 4: The deferred test — `StageVerifyScreen`

Write `mobile/test/screens/stage_verify_screen_test.dart`. Cover the cases
plan 002 deferred:
- `verifyStage` mocked to return a matched result → verified state renders
  simulated data.
- `verifyStage` throws after `_maxAttempts` hand attempts → phase switches to
  face (banner text asserted).
- Face phase `verifyStage` throws → phase switches to override (supervisor
  override button visible).

**Verify**: `cd mobile && flutter test test/screens/stage_verify_screen_test.dart` → all pass.

## Test plan

- `cd mobile && flutter test` → all pass, including the two new screen test
  files and the existing smoke test (should not regress).
- `cd mobile && flutter analyze` → no new errors.

## Done criteria

ALL must hold:

- [ ] `mocktail` is a `mobile/pubspec.yaml` dev dependency.
- [ ] `mobile/test/support/` exists with the three helpers described above.
- [ ] `hand_verification_screen_test.dart` and `stage_verify_screen_test.dart`
      exist and pass.
- [ ] `cd mobile && flutter test` exits 0.
- [ ] `cd mobile && flutter analyze` has no new issues vs. the pre-plan baseline.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 015 updated.

## STOP conditions

Stop and report back (do not improvise) if:
- `mocktail` cannot mock one of the concrete service classes (e.g. due to a
  `factory` constructor or heavy static state) — report which class and
  whether an interface extraction is truly required before proceeding; do
  not silently refactor the service architecture to work around it.
- The `camera` plugin's test helpers don't support the `isHandCapture`/
  `showFingerprintOverlay` code paths in `CameraScreen` without a live
  platform channel — report and propose whether to fake at the
  `CameraScreen` boundary instead (return a canned `XFile` via a testable
  seam) rather than mocking the plugin itself.

## Maintenance notes

- Once this lands, treat "no widget test" as a real gap for any future UI
  plan touching `mobile/lib/screens/` — the excuse plan 002 used (no
  infrastructure exists) no longer applies after this plan ships.
- Keep `test/support/` growing incrementally as new mocks are needed, rather
  than each screen test hand-rolling its own fakes again.
