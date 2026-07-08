# Plan 001: Establish a runnable Python-service test suite and a CI baseline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report — do not
> improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- python-service/tests python-service/requirements.txt`
> If any in-scope file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests / dx
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

The Python biometric service is the code the project exists for (segmentation →
embedding → FAISS → score fusion), and it has effectively no automated safety
net. Its single test file, `python-service/tests/test_four_finger.py`, is a
hand-rolled script that runs under `if __name__ == "__main__"` with its own
`check()` counter — no test runner discovers it, CI cannot run it, and its two
most meaningful tests `return` early ("skipping") whenever the RidgeBase dataset
or the ONNX model are absent, which is exactly the CI/dev condition. There is
also no CI at all: no `.github/workflows`. A silent break in fusion arithmetic
or FAISS round-tripping would not surface until a live demo. This plan makes the
Python suite `pytest`-runnable with at least one assertion that always runs, and
adds a CI workflow that runs all three suites. It is a prerequisite for plans
002 and 011, which need a real test to prove behavior.

## Current state

- `python-service/tests/test_four_finger.py` — the only Python test. Structure:
  - Defines its own harness at the top:
    ```python
    _passed = 0
    _failed = 0
    def check(cond, label): ...   # increments _passed/_failed, prints
    ```
  - `test_real_selfmatch` and `test_embedding_path` bail out early when data or
    the ONNX model is missing:
    ```python
    if not RIDGEBASE_DIR.exists():
        print("  … skipping (RidgeBase not present)")
        return
    ```
  - Runs via `if __name__ == "__main__":` at the bottom, not via `pytest`.
- `python-service/requirements.txt` — no `pytest`, `httpx`, or `coverage`:
  ```
  fastapi>=0.115
  uvicorn[standard]>=0.30
  opencv-python-headless>=4.9
  numpy>=1.26
  pillow>=10.0
  python-multipart>=0.0.9
  insightface>=0.7.3
  onnxruntime>=1.19
  faiss-cpu>=1.8
  scipy>=1.13
  matplotlib>=3.8  # optional — only used by tools/calibrate_far_frr.py for plots
  ```
- No `pyproject.toml` / `pytest.ini` anywhere in `python-service/`.
- No `.github/workflows/` directory in the repo root.
- Laravel already has a one-command suite: `composer test` (defined in
  `laravel/composer.json` scripts → `@php artisan config:clear` + `@php artisan test`).
- Flutter has `mobile/test/widget_test.dart` runnable via `flutter test`.

The two functions that CAN be tested without external assets today are the pure
ones: **score fusion** in `python-service/app/services/matcher.py` (look for the
fusion function, named `fuse_scores` or similar around line 200) and **FAISS
add/search round-trips** in `python-service/app/services/faiss_service.py`
(`enroll` / `identify` / `remove_patient`, which operate on plain float vectors).

Repo Python conventions: modules use `from __future__ import annotations`,
type hints, and module-level functions (not classes) for services. Match that in
test files.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Create/enter venv | `cd python-service && python3 -m venv venv && . venv/bin/activate` (a `venv/` already exists — activate it) | prompt shows `(venv)` |
| Install deps | `pip install -r requirements.txt` | exit 0 |
| Run Python tests | `cd python-service && python -m pytest -q` | all pass, exit 0 |
| Run Laravel tests | `cd laravel && composer test` | all pass |
| Run Flutter tests | `cd mobile && flutter test` | all pass |

## Scope

**In scope** (the only files you should create or modify):
- `python-service/requirements-dev.txt` (create)
- `python-service/pytest.ini` (create)
- `python-service/tests/test_four_finger.py` (convert to pytest, keep behavior)
- `python-service/tests/test_matcher_fusion.py` (create)
- `python-service/tests/test_faiss_roundtrip.py` (create)
- `python-service/tests/conftest.py` (create, if fixtures are needed)
- `.github/workflows/ci.yml` (create)

**Out of scope** (do NOT touch):
- Any file under `python-service/app/` — this plan adds tests only, it does not
  change service behavior. If a test reveals a bug, record it and STOP; the fix
  belongs to another plan.
- `python-service/tools/` calibration scripts.
- Committing any real RidgeBase images or the ONNX model (both are gitignored and
  large; do not add them).

## Git workflow

- Branch: `advisor/001-python-test-ci-baseline`
- Commit per logical unit (deps, pytest conversion, new tests, CI). Message style
  matches repo history (short imperative, e.g. "Add pytest harness for Python service").
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a dev-requirements file and pytest config

Create `python-service/requirements-dev.txt`:
```
-r requirements.txt
pytest>=8.0
```
Create `python-service/pytest.ini`:
```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
```

**Verify**: `cd python-service && . venv/bin/activate && pip install -r requirements-dev.txt` → exit 0.

### Step 2: Convert the existing script to pytest without weakening it

In `python-service/tests/test_four_finger.py`:
- Replace the custom `check(cond, label)` calls with plain `assert cond, label`.
- Remove the `_passed`/`_failed` counters and the `if __name__ == "__main__"` runner.
- Keep the early-`return` skips but convert them to `pytest.importorskip` /
  `pytest.skip(reason=...)` so a skipped test is *reported as skipped*, not
  silently passed. Example:
  ```python
  import pytest
  def test_real_selfmatch():
      if not RIDGEBASE_DIR.exists():
          pytest.skip("RidgeBase dataset not present")
      ...
  ```

**Verify**: `cd python-service && python -m pytest -q tests/test_four_finger.py` → the
synthetic-hand and fusion assertions pass; asset-dependent tests report `s`
(skipped), not `.` (passed).

### Step 3: Add always-on unit tests for score fusion

Create `python-service/tests/test_matcher_fusion.py`. First open
`python-service/app/services/matcher.py:164` and read the actual `fuse_scores`
signature (`fuse_scores(scores: list[float], method: str = "mean") -> float`;
it is pure). Write tests that call it directly:
- happy path: 4 finger scores → expected fused score (assert the exact arithmetic
  the function documents).
- fewer than 4 fingers present (e.g. 2 or 3) → fusion still returns a valid score
  and does not divide by zero.
- empty input → returns 0.0 or raises a clear error (assert whichever the code
  actually does; do not change the code to match your test — if it crashes
  ungracefully, that is a STOP-and-report finding, not something to fix here).
- **invariant, not just exact value**: higher input scores never produce a lower
  fused score than lower input scores, e.g.
  `fuse_scores([0.9]*4) > fuse_scores([0.4]*4)`. Also assert the fused score stays
  within whatever range the function documents (e.g. `0.0 <= result <= 1.0` if
  scores are similarities). Exact-arithmetic tests alone can keep passing after a
  refactor that preserves the formula but breaks the ordering the whole system
  depends on — the invariant test is what actually catches that.

**Verify**: `cd python-service && python -m pytest -q tests/test_matcher_fusion.py` → all pass.

### Step 4: Add always-on FAISS round-trip tests

Create `python-service/tests/test_faiss_roundtrip.py`. `faiss_service` uses
module-level globals and an on-disk index; point it at a temp dir so tests are
isolated. Read `python-service/app/services/faiss_service.py` for the exact
globals (`_INDEX_DIR`, `_INDEX_FILE`, `_META_FILE`), the dimensionality constant
`EMBEDDING_DIM` (currently `512` — confirmed present at line 41; use the live
constant, do not hard-code `512` separately, so the test can't silently drift
from the service), and public functions (`enroll(patient_id, template_id,
embedding)`, `identify(embedding, top_k)`, `remove_patient(patient_id)`,
`rebuild(templates)`). Write tests that:
- monkeypatch the index dir to a `tmp_path` and re-run `initialise()` /
  `rebuild([])` so each test starts empty,
- **empty-index case**: on a freshly rebuilt/empty index, `identify(some_vector)`
  returns `[]` (or whatever empty-result shape the code defines), not an
  exception. Production bugs cluster in fresh-deployment / first-enrollment /
  empty-index states — this is the cheapest test that guards against that class
  and should be written before the two-patient round-trip below.
- enroll two distinct `EMBEDDING_DIM`-dim vectors for two patients, then
  `identify` with a vector near patient A → A ranks first with the higher score,
- `remove_patient(A)` → subsequent `identify` no longer returns A.

Use small deterministic vectors (e.g. `[1.0, 0.0, 0.0, ...]`). Do NOT use random
vectors — the harness forbids `Math.random`-style nondeterminism in committed tests.

**Verify**: `cd python-service && python -m pytest -q tests/test_faiss_roundtrip.py` → all pass.

### Step 5: Add a CI workflow running all three suites

Create `.github/workflows/ci.yml` with three jobs:
- `python`: setup Python 3.12, `pip install -r python-service/requirements-dev.txt`,
  `cd python-service && python -m pytest -q`.
- `laravel`: setup PHP 8.3, `cd laravel && composer install --no-interaction`,
  copy `.env.example` to `.env`, `php artisan key:generate`, `composer test`.
- `flutter`: setup Flutter stable, `cd mobile && flutter pub get && flutter test`.

Trigger on `push` and `pull_request`. Keep jobs independent (no `needs:`) so one
failing suite does not mask another.

**Verify**: `python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` →
exit 0 (valid YAML). (You cannot run GitHub Actions locally; validating the YAML
and confirming each job's commands match the working local commands from the table
above is the bar.)

## Test plan

- New tests: `test_matcher_fusion.py` (4 cases: happy path, partial fingers,
  empty input, ordering/range invariant), `test_faiss_roundtrip.py` (4 cases:
  empty-index identify, two-patient rank, removal, plus isolation setup), plus
  the converted `test_four_finger.py` (unchanged assertions, now
  pytest-discovered).
- Structural pattern: there is no prior pytest file, so follow the FastAPI/pytest
  idiom (plain `def test_*` functions, `assert`, `tmp_path`/`monkeypatch`
  fixtures). Keep imports at module top with `from __future__ import annotations`.
- Verification: `cd python-service && python -m pytest -q` → all non-skipped tests
  pass; at least 8 new/converted assertions run without external assets.

## Done criteria

ALL must hold:

- [ ] `cd python-service && python -m pytest -q` exits 0 with ≥8 passing tests and
      0 failures (asset-dependent tests may be `skipped`, never silently passed).
- [ ] `python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` exits 0.
- [ ] `grep -n "if __name__" python-service/tests/test_four_finger.py` returns nothing.
- [ ] No files under `python-service/app/` are modified (`git status`).
- [ ] `plans/README.md` status row for 001 updated.

## STOP conditions

Stop and report back (do not improvise) if:
- The fusion or FAISS code in "Current state" doesn't match the live code
  (drifted since this plan).
- Writing an honest test reveals an actual bug in `app/` code (e.g. fusion divides
  by zero on empty input) — report it as a finding; do NOT fix `app/` here.
- `pip install -r requirements-dev.txt` fails to build `faiss-cpu`/`onnxruntime`
  on the CI Python version — report the version mismatch instead of pinning blindly.

## Maintenance notes

- When plans 002 and 011 change scoring/pipeline behavior, extend these tests
  rather than mocking around them.
- A reviewer should confirm the skipped tests are genuinely asset-gated (not
  hiding failures) and that the FAISS tests are isolated (no writes to the real
  `face_index/` dir).
- Deferred: a real Laravel↔Python contract test (recorded as TEST-03) is out of
  scope here; it belongs in a follow-up once the pipeline in 002 is repaired.
- CI dependency risk (accepted, not fixed here): `insightface`/`onnxruntime`/
  `faiss-cpu` are fragile to install on GitHub-hosted runners. This plan keeps
  the STOP-and-report behavior in Step 5/STOP conditions rather than pinning
  wheels or restructuring requirements. If CI reliably fails on runner dependency
  install (not a real test failure), the fix is a follow-up plan that splits
  `requirements.txt` into `requirements.txt` / `requirements-ml.txt` — do not
  attempt that split inside this plan.
