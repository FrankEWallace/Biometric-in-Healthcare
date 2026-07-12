# Plan 012: Remove dead code, fix misleading naming, and split dependencies

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- python-service/`
> If files changed, re-verify the "no importers" claims below before deleting
> anything; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

Three low-risk hygiene issues that slow every future change to the biometric stack:

1. **Two unused parallel feature-extraction implementations** sit next to the real
   matcher (`processor.py`, `feature_extractor.py`), creating "which one is live?"
   confusion for exactly the code that most needs clarity.
2. **One template format has three names** across the stack — a module named
   "sourceafis" that wraps a homegrown crossing-number minutiae matcher (not the
   SourceAFIS library), docblocks calling it an "ORB template", and route docs
   calling it "SourceAFIS". "SourceAFIS" falsely implies a third-party dependency.
3. **A plotting-only dependency (`matplotlib`) ships in the runtime service image**,
   though it's used only by an offline calibration script — bloating the production
   image and widening the supply-chain surface.

Each fix is mechanical and independently verifiable.

## Current state — verify each before acting

Run these to confirm nothing imports the dead modules (must return no hits other
than the files' own definitions/docstrings):
```
grep -rn "import processor\|from app.services.processor\|from app.services import processor" python-service/app python-service/tools python-service/tests
grep -rn "feature_extractor" python-service/app python-service/tools python-service/tests
```
At `a05e716`, `feature_extractor` appears only inside its own docstring, and
`processor` references resolve to `image_processor` (a different, live module).
**Re-run and confirm** before deleting.

Naming (read to confirm):
- `python-service/app/services/sourceafis_service.py` — module wrapping the
  minutiae matcher, not the SourceAFIS library.
- `laravel/app/Services/FingerprintService.php` docblocks (around lines 68, 74–87)
  refer to an "ORB template".
- `python-service/app/routes/fingerprint.py` route docs say "SourceAFIS".
- `python-service/app/services/matcher.py` tags the format `minutiae_v1` — the one
  true name.

Dependencies:
- `python-service/requirements.txt` includes:
  `matplotlib>=3.8  # optional — only used by tools/calibrate_far_frr.py for plots`

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Confirm no importers | the two greps above | no hits outside the files themselves |
| Python tests | `cd python-service && python -m pytest -q` | all pass |
| Laravel tests | `cd laravel && composer test` | all pass |
| Service boots | `cd python-service && python -c "import app.main"` | exit 0, no ImportError |

## Scope

**In scope**:
- Delete: `python-service/app/services/processor.py`,
  `python-service/app/services/feature_extractor.py` (only if the grep confirms zero importers)
- Rename/re-doc: `python-service/app/services/sourceafis_service.py` and its
  importers; scrub "ORB"/"SourceAFIS" wording in `FingerprintService.php` docblocks
  and `fingerprint.py` route docs
- `python-service/requirements.txt` (remove matplotlib)
- `python-service/requirements-tools.txt` (create — for the calibration extras)

**Out of scope** (do NOT touch):
- Runtime matching behavior — this is naming + deletion only, no logic change.
- `tools/calibrate_far_frr.py` logic (it will import matplotlib from the tools reqs).
- The `minutiae_v1` format string itself (it's the canonical name; keep it).

## Git workflow

- Branch: `advisor/012-cleanup-deadcode-naming-deps`
- One commit per item (delete dead code / rename / deps). Short imperative messages.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Delete the unused feature-extraction modules

After re-confirming zero importers with the greps in "Current state", delete
`python-service/app/services/processor.py` and
`python-service/app/services/feature_extractor.py`. Git history preserves them.

**Verify**: `cd python-service && python -c "import app.main"` → exit 0 (no
ImportError), and `cd python-service && python -m pytest -q` → still green.

### Step 2: Rename the misnamed minutiae module and scrub wording

Rename `sourceafis_service.py` → `minutiae_matcher.py` (or `minutiae_service_wrapper.py`
if a name clash with the existing `minutiae_service.py` is confusing — pick the
clearer one). Update every importer (grep `sourceafis_service` across
`python-service/`). Then scrub misleading wording:
- In `laravel/app/Services/FingerprintService.php` docblocks: replace "ORB template"
  with "crossing-number minutiae template (`minutiae_v1`)".
- In `python-service/app/routes/fingerprint.py`: replace "SourceAFIS" references
  with "crossing-number minutiae".

Do NOT change any behavior, method names that are part of the matcher interface, or
the `minutiae_v1` format tag — only the module filename, its imports, and comments/
docblocks.

**Verify**: `grep -rin "sourceafis\|ORB template" python-service/app laravel/app` →
no matches (or only in historical/changelog docs, not live code/docblocks);
`cd python-service && python -m pytest -q` and `cd laravel && composer test` → green.

### Step 3: Move matplotlib out of the runtime requirements

Create `python-service/requirements-tools.txt`:
```
-r requirements.txt
matplotlib>=3.8
```
Remove the `matplotlib>=3.8` line from `python-service/requirements.txt`. If plan
001's `requirements-dev.txt` exists, that's separate (test deps) — keep tools and
dev split or merge per what's cleanest, but matplotlib must not remain in the base
`requirements.txt`.

**Verify**: `grep -n matplotlib python-service/requirements.txt` → no matches;
`grep -n matplotlib python-service/requirements-tools.txt` → one match.

## Test plan

- No new behavioral tests (mechanical cleanup). The existing suites plus the
  `import app.main` smoke check are the guard: nothing should break.
- Verification: both suites green; service imports cleanly; greps confirm the
  deletions/renames/dep removal.

## Done criteria

ALL must hold:

- [ ] `processor.py` and `feature_extractor.py` deleted; `python -c "import app.main"` exits 0.
- [ ] No live code or docblock references `sourceafis` or "ORB template"; the
      renamed module's importers all updated.
- [ ] `matplotlib` absent from `python-service/requirements.txt`, present in
      `python-service/requirements-tools.txt`.
- [ ] `cd python-service && python -m pytest -q` and `cd laravel && composer test` both exit 0.
- [ ] No runtime behavior changed (no method-body edits).
- [ ] `plans/README.md` status row for 012 updated.

## STOP conditions

Stop and report back if:
- The greps show ANY importer of `processor.py`/`feature_extractor.py` (including a
  dynamic import via `importlib`) — do NOT delete; report it.
- Renaming `sourceafis_service` breaks an import you can't locate — revert the
  rename and report.
- `tools/calibrate_far_frr.py` imports matplotlib at module top and is imported by
  runtime code (it shouldn't be) — report before removing matplotlib from base reqs.

## Maintenance notes

- Keep runtime `requirements.txt` free of tooling-only deps going forward; add new
  plotting/calibration deps to `requirements-tools.txt`.
- The "SourceAFIS" name implied an interoperability guarantee that never existed;
  after this rename, don't reintroduce it unless the real SourceAFIS library is
  actually adopted.
- Reviewer should confirm the diff contains no logic changes — only deletions,
  renames, imports, comments, and requirements files.

---

## Addendum (2026-07-11, commit `d25ce31`) — Flutter dead-code & duplication

> Added after the four-finger pipeline unification (plans 002/010) orphaned the
> legacy single-finger mobile surface. This is a SEPARATE, self-contained work
> item from the Python cleanup above — do it on its own branch
> (`advisor/012b-flutter-deadcode`) with its own drift check:
> `git diff --stat d25ce31..HEAD -- mobile/lib/`. All "no caller" claims below
> were grep-verified at `d25ce31`; **re-verify each before deleting** (STOP if
> any importer appears). Commands: `cd mobile && dart analyze` (0 errors, 9
> pre-existing info lints OK) and `flutter test` (smoke test must pass) gate
> every step.

> **Status (2026-07-12): Parts A, B, C, D DONE** — A + D merged via PR #21;
> C after plan 019; B (this addendum) collapses the dead gallery path. All four
> parts of the 012b addendum are now complete.

### A. Dead single-finger service + screen chain (grep-verified no callers) — DONE

- `mobile/lib/services/fingerprint_service.dart` — `enrollGallery()` (~:352),
  `verifyFingerprint()` (~:408): **zero callers** in `lib/`.
- `registerFingerprint()` (~:304): only caller is
  `mobile/lib/screens/camera_screen.dart:271`; `CameraScreen` is only
  constructed by `mobile/lib/screens/fingerprint_capture_screen.dart`, which
  has **no external references**. The whole chain
  `fingerprint_capture_screen.dart → camera_screen.dart → registerFingerprint()`
  (including `CameraScreen`'s `showFingerprintOverlay` mode) is unreachable.
- Orphaned result models in `fingerprint_service.dart` with no references
  outside that file: `FingerprintRegisterResult`, `FingerprintGalleryEnrollResult`,
  `FingerprintVerifyResult` (+ any `FingerprintErrorKind` values used only by them).
- **Action**: delete `fingerprint_capture_screen.dart` and `camera_screen.dart`;
  remove the three methods and three orphaned models. Confirm with
  `grep -rn "CameraScreen\|verifyFingerprint\|enrollGallery\|registerFingerprint\|FingerprintCaptureScreen" mobile/lib --include="*.dart"` → only self-references remain, then `dart analyze` clean. Effort S, risk LOW.
- **STOP** if any real screen still imports `CameraScreen` (the four-finger
  screens use `FingerprintLivenessCameraScreen`, not `CameraScreen` — but the
  in-flight iOS work is uncommitted; re-grep against the live tree).

### B. Dead gallery multi-shot path in FingerprintLivenessCameraScreen — DONE

> **Status (2026-07-12): DONE** — premise re-verified against the live tree
> (both callers pass `galleryTarget: 1` and read only `capture.captures.first`,
> never `livenessToken`). Removed `galleryMode`/`galleryTarget`, the
> `FingerprintGalleryResult` class, `_startGalleryCapture()`,
> `_ScreenState.repositioning`, `_GalleryProgressBar`, `_galleryShots`, and the
> "shift your hand" reposition UI. Both enroll screens now consume the popped
> `XFile` directly (`File(capture.path)`). The single-capture path
> (`_startCapture` → pops `frames.last`) is unchanged and is now the only path,
> so the STOP condition did not trigger. `dart analyze` 0 errors (9 pre-existing
> info lints); `flutter test` green. Mobile-only — no server/VPS change.

- Both `galleryMode: true` call sites pass `galleryTarget: 1`
  (`mobile/lib/screens/patient_registration_screen.dart:130-131`,
  `mobile/lib/screens/clerk/fingerprint_enroll_screen.dart:47-48`); no other
  `galleryMode` construction exists. With target 1 the multi-shot loop
  (`fingerprint_liveness_camera_screen.dart` ~:485-513) never runs, so
  `_ScreenState.repositioning`, `_GalleryProgressBar`'s reposition branch, and
  the "shift your hand" instruction are unreachable.
- `FingerprintGalleryResult.livenessToken` is populated but **never consumed**
  (both callers use only `capture.captures.first` and call `enrollHand()`,
  which takes no liveness token) — the gallery-enroll endpoint it was built for
  is the dead `enrollGallery()` from part A.
- **Action** (effort M, risk MED — interwoven with the live capture state
  machine): collapse `galleryMode` to a single-capture pop (or remove it and
  have the two enroll screens consume the plain `XFile`), dropping
  `galleryTarget`, `_GalleryProgressBar`, `_ScreenState.repositioning`, and the
  `livenessToken` plumbing. Do this AFTER part A. **STOP** if collapsing risks
  the single-capture path — report and leave as-is.

### C. Consolidate duplicated private widgets/helpers — DONE

> **Status (2026-07-12): DONE** — after plan 019 merged (so its copied
> `_showAccessRestrictedDialog` folded into the consolidation). Extracted five
> shared widgets into `mobile/lib/widgets/`: `HandOption`, `ErrorBanner` (superset
> with optional `onRetry`), `VerifyingView` (parameterized `title`/`subtitle` —
> the copies had drifted per-screen), `CaptureBadge` (renamed from `_Badge` to
> avoid Material's `Badge`), and `showAccessRestrictedDialog()`. Removed the four
> `_showAccessRestrictedDialog` copies and all private duplicates across 7 screens
> (−731 lines). Minor reconciliations: `patient_registration`'s error banner
> adopted the canonical padding, and `verification_screen`'s access dialog gained
> the referral sentence. `dart analyze` 0 errors; `flutter test` passes.

Grep-verified duplicate sites (extract into `mobile/lib/widgets/`, effort M,
risk LOW–MED — mechanical, watch for silently-drifted copies):

- `_HandOption` ×4: `verification_screen.dart:551`,
  `verify/multimodal_verification_screen.dart:369`,
  `verify/hand_verification_screen.dart:410`, `visit/stage_verify_screen.dart:697`.
- `_verifyHandBothSides` ×2 (identical bodies): `clerk/clerk_scan_screen.dart:144`,
  `clerk/visit_detail_screen.dart:123` — extract to a `FingerprintService`
  method or shared helper (also relevant to CORRECT: a fix must currently be
  applied twice).
- `_ErrorBanner` ×6, `_VerifyingView` ×4, `_Badge` ×3 (locations in the audit
  notes; re-grep to confirm before touching).
- Note: plan 019 intentionally copies `_showAccessRestrictedDialog` into the
  multimodal screen; fold that into this consolidation too.

### D. Related correctness note (not a deletion — see also) — DONE

`_verifyHandBothSides` issued TWO full `/verify/hand` 1:N calls per user
"attempt" on a right-hand no-match (one right, one left), so one attempt could
produce two server verification-log rows and double the server throttle spend,
while the client `_attempts` counter incremented once.

**Resolved (2026-07-12, PR #21) via the "single both-hands server match" option:**
`VerificationController::verifyHand` now accepts `hand='both'`. It loads the
candidate gallery once, scores each orientation with a stateless
`scoreHandOrientation()` helper, keeps the higher fused score, and writes a
**single** verification log + audit row per attempt. A `right`/`left` request is
unchanged (exactly one `processHand` + one `matchHand`). Both clerk
`_verifyHandBothSides` helpers collapse to one `verifyHand(hand: 'both')` call,
and `HandVerifyAccessControlTest::both_hands_mode_writes_one_verification_log`
locks in the one-row-per-attempt guarantee.
