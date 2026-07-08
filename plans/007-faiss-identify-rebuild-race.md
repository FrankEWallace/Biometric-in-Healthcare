# Plan 007: Fix the FAISS identify/rebuild race in the Python service

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- python-service/app/services/faiss_service.py`
> If the file changed, compare the "Current state" excerpts against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001 (for the FAISS round-trip tests to extend)
- **Category**: bug
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

`faiss_service.identify()` reads the module-global `_index` and `_id_map` without
holding `_lock`, and it does so across *multiple* operations: it calls
`_index.search(...)` and then indexes into `_id_map[pos]`. Meanwhile
`_do_rebuild()` (invoked under `_lock` by `rebuild()` and by `_maybe_compact()`,
which fires on the `remove_patient` write path) reassigns `_index`, `_id_map`, and
`_deleted` to brand-new objects. If an `identify` searches the *old* index (whose
positions are valid for the *old* `_id_map`) and then, after a concurrent rebuild
swaps the globals, indexes into the *new* `_id_map`, it can:
- return a **different patient's** `patient_id`/`template_id` (a patient-
  misidentification hazard in a hospital ID system), or
- raise `IndexError` if the new map is shorter.

The self-heal rebuild fired mid-request from Laravel's `FaceController::verify`
makes this window reachable under normal load. The fix is to have `identify` take
a consistent snapshot of the three globals (index + id_map + deleted) under the
lock, then operate only on that snapshot.

## Current state

`python-service/app/services/faiss_service.py`:

Module docstring claims identify is lock-free (around lines 22–24):
```
identify() is lock-free because FAISS FlatIP search is read-only on the index object.
```
Globals and lock (around lines 52+):
```python
_lock = Lock()
_index = None
_id_map: list[dict] = []
_deleted: set[int] = set()
```
`identify()` (around lines 214–258) reads globals directly and interleaves search
with `_id_map[pos]`:
```python
def identify(embedding, top_k=10):
    initialise()
    active = _index.ntotal - len(_deleted)
    if active == 0:
        return []
    vec = _normalise(np.array(embedding, dtype=np.float32))
    k = min(top_k * 4 + len(_deleted), _index.ntotal)
    while True:
        D, I = _index.search(vec, int(k))
        best = {}
        for score, pos in zip(D[0].tolist(), I[0].tolist()):
            if pos < 0 or pos in _deleted:
                continue
            meta = _id_map[pos]        # ← _id_map may have been swapped since search
            ...
        if len(best) >= top_k or k >= _index.ntotal:
            break
        k = min(k * 2, _index.ntotal)
    return sorted(...)[:top_k]
```
`_do_rebuild()` (around lines 136–162) reassigns all three globals; `rebuild()`
(line 261) and `_maybe_compact()` (line 116, called from `remove_patient` at line
210) run it under `with _lock:`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Python tests | `cd python-service && python -m pytest -q` | all pass |
| Filter | `cd python-service && python -m pytest -q tests/test_faiss_roundtrip.py` | pass |

## Scope

**In scope**:
- `python-service/app/services/faiss_service.py` (`identify()` snapshotting; update the docstring)
- `python-service/tests/test_faiss_roundtrip.py` — add a concurrency/consistency test (this file is created in plan 001)

**Out of scope** (do NOT touch):
- The rebuild/compact logic itself — it already holds the lock correctly.
- `enroll` / `remove_patient` write-path logic.
- The Laravel side.

## Git workflow

- Branch: `advisor/007-faiss-identify-rebuild-race`
- One commit for the snapshot fix, one for the test.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Snapshot the three globals under the lock

At the top of `identify()`, after `initialise()`, take a consistent reference to
all three globals while holding `_lock`, then operate only on the local
references for the rest of the function:
```python
def identify(embedding, top_k=10):
    initialise()
    with _lock:
        index   = _index
        id_map  = _id_map
        deleted = _deleted          # frozenset(_deleted) if you want an immutable copy
    active = index.ntotal - len(deleted)
    if active == 0:
        return []
    vec = _normalise(np.array(embedding, dtype=np.float32))
    k = min(top_k * 4 + len(deleted), index.ntotal)
    while True:
        D, I = index.search(vec, int(k))
        ...
            meta = id_map[pos]
        ...
```
Because `_do_rebuild` reassigns the globals to *new* objects (rather than mutating
in place), capturing the references under the lock guarantees `index` and `id_map`
belong to the same generation for the whole call. Use the local names (`index`,
`id_map`, `deleted`) everywhere below — do not reference the globals again.

Note: the FAISS `search` C-call itself is kept *outside* the lock so searches
still run concurrently; only the reference capture is locked. If you prefer
maximum safety over concurrency, holding `_lock` for the whole function is also
acceptable at the documented index sizes (hundreds–thousands) — but the snapshot
approach is preferred.

**Verify**: `grep -n "with _lock" python-service/app/services/faiss_service.py` →
now also appears at the top of `identify`.

### Step 2: Correct the docstring

Update the module docstring (lines ~22–24) to state that `identify` snapshots the
index/id_map/deleted references under the lock to stay consistent with rebuilds,
rather than claiming it is lock-free.

**Verify**: `grep -n "lock-free" python-service/app/services/faiss_service.py` →
no longer claims identify is lock-free (or the line is corrected).

### Step 3: Add a consistency test

In `python-service/tests/test_faiss_roundtrip.py` (created in plan 001), add a
test that interleaves `identify` with `rebuild`/`remove_patient` and asserts no
`IndexError` and no cross-patient id return. A deterministic way without real
threads: build an index, capture a snapshot via `identify` behavior, then call
`rebuild` with a *shorter* template list and confirm a subsequent `identify`
returns only valid, in-range patient ids (never an index past the new map). If you
use threads, keep them bounded and join them; do not rely on timing/`sleep`.

**Verify**: `cd python-service && python -m pytest -q tests/test_faiss_roundtrip.py` → passes.

## Test plan

- New case in `test_faiss_roundtrip.py`: rebuild-to-shorter-map followed by
  identify never raises and never returns an out-of-range/other-patient id.
- Verification: `cd python-service && python -m pytest -q` → green.

## Done criteria

ALL must hold:

- [ ] `identify()` captures `_index`/`_id_map`/`_deleted` under `_lock` and uses
      only local references thereafter (no global reads after the snapshot).
- [ ] Module docstring no longer claims `identify` is lock-free.
- [ ] `cd python-service && python -m pytest -q` exits 0; the new consistency test passes.
- [ ] No files outside the in-scope list modified (`git status`).
- [ ] `plans/README.md` status row for 007 updated.

## STOP conditions

Stop and report back if:
- `_do_rebuild` turns out to mutate the existing `_id_map`/`_index` *in place*
  rather than reassigning new objects — then a reference snapshot is insufficient
  and you must hold the lock for the whole `identify` (report this; it changes the
  approach).
- The FAISS `search` call requires the GIL to be held in a way that makes the
  snapshot approach unsafe — fall back to whole-function locking and report.

## Maintenance notes

- If the index grows to a size where whole-function locking would serialize
  searches unacceptably, the snapshot approach (Step 1) is the one to keep.
- Reviewer should confirm no code path reads `_index`/`_id_map` globals after the
  snapshot inside `identify`.
- This complements plan 006 (Laravel-side enroll/index consistency); together they
  close the DB↔index divergence and the in-service race.
