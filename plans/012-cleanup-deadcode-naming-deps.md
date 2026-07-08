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
