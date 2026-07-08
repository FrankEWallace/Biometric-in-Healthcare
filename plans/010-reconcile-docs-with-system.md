# Plan 010: Reconcile docs & agent instructions with the live system

> **Executor instructions**: Follow this plan step by step. Verify each claim
> against the live code before writing it into docs. If anything in "STOP
> conditions" occurs, stop and report. When done, update the status row for this
> plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- README.md CLAUDE.md docs/`
> If any changed, re-read them before editing. NOTE: `docs/docs.json`,
> `docs/mint.json`, and `docs/api-reference/overview.mdx` already show as modified
> in the working tree — read their current content first.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: best run after 002 and 009 so docs describe the fixed state
- **Category**: docs
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

The docs have drifted from the code in ways that matter for an FYP defense and for
any agent onboarded from this repo:

1. **Two Mintlify configs coexist.** `docs/mint.json` (deprecated schema) and
   `docs/docs.json` (current schema) both declare the same site; both were edited
   this session. Mintlify reads one canonical file — keeping both invites nav drift.
2. **README overstates the contactless feature as "delivered" without qualifier**
   in one place while correctly calling it advisory in another — an internal
   contradiction an examiner will catch.
3. **The contactless roadmap is stale.** It marks the mobile hand-capture UI as
   "blocked (Flutter toolchain not installed)" and the ONNX embedding matcher as
   "scaffolded, inactive" — but the capture screen exists and is routed
   (`mobile/lib/screens/verify/hand_verification_screen.dart` mounted in
   `app_shell.dart`), and the ONNX model file, threshold env var, and wiring are
   all present. The doc understates delivered work.
4. **`CLAUDE.md` describes a different, earlier system** — "Python + OpenCV",
   "Flask or FastAPI", single-fingerprint register/verify — with no mention of the
   four-finger contactless pipeline, ONNX embeddings, face recognition, or the
   multimodal decision matrix that dominate the real codebase. Any agent starting
   from it builds a wrong mental model.

This plan is documentation-only: reconcile the docs to the verified state of the
code. It changes no behavior.

## Current state — verify each before editing

Confirm these against the live tree (they were true at `a05e716`; re-check):
- `docs/mint.json` AND `docs/docs.json` both exist. Determine which Mintlify
  actually uses (current Mintlify uses `docs.json`; `mint.json` is the legacy
  name). `grep -n "\"name\"\|navigation" docs/docs.json docs/mint.json`.
- `README.md` around line 47 and line ~365 describe the hand photo as "matched via
  a learned ONNX embedding (Ridgeformer)" with no qualifier, while another README
  line (~372) says `verify/hand` is advisory until the matcher/threshold are
  installed. Read both.
- `docs/contactless-fingerprint-roadmap.md` status table — read the "Implementation
  status" and "Remaining before a real contactless demo" sections.
- The **actual** live state to describe (verify by reading):
  - `python-service/models/contactless_embedding.onnx` exists (`ls python-service/models`).
  - `laravel/config/services.php` reads `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD`
    (threshold plumbing is live); `laravel/.env` sets it (do NOT copy the value).
  - `mobile/lib/screens/verify/hand_verification_screen.dart` exists and is mounted
    in `mobile/lib/screens/shell/app_shell.dart`.
  - Whether `verify/hand` currently decides or stays advisory depends on the
    registered matcher name check in `VerificationController` (`$usingPlaceholder =
    ! str_contains($matcherName, 'embedding')`). Read it and describe the *actual*
    current behavior — do not assume.
- `CLAUDE.md` — the tech-stack and core-features sections describe the old scope.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| List config files | `ls docs/*.json` | shows both files |
| Confirm model present | `ls python-service/models` | lists `contactless_embedding.onnx` |
| Mintlify build (if installed) | `cd docs && npx mint dev` (or the repo's documented command) | builds without nav errors |

## Scope

**In scope**:
- `docs/mint.json` (delete, once `docs.json` confirmed canonical)
- `README.md` (qualify the contactless feature claims)
- `docs/contactless-fingerprint-roadmap.md` (update stale status rows)
- `CLAUDE.md` (refresh tech-stack + core-features to match reality)

**Out of scope** (do NOT touch):
- Any code file — this is docs-only.
- The other already-modified docs in the working tree (`docs/docs.json`,
  `docs/api-reference/overview.mdx`) beyond what's needed to confirm canonical
  config — do not revert the user's in-progress edits.
- Do NOT invent capabilities; describe only what the code does.

## Git workflow

- Branch: `advisor/010-reconcile-docs`
- One commit per doc. Short imperative messages.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Consolidate to a single Mintlify config

Confirm `docs/docs.json` is the canonical config (current Mintlify schema). If so,
delete `docs/mint.json`. If the deprecated `mint.json` contains nav entries NOT
present in `docs.json`, port them into `docs.json` first, then delete `mint.json`.

**Verify**: `ls docs/mint.json` → "No such file"; `docs/docs.json` still present and valid JSON (`python -c "import json;json.load(open('docs/docs.json'))"` → exit 0).

### Step 2: Qualify the README contactless claims

Edit the two README lines that state ONNX matching as delivered so they match the
verified runtime behavior (from Current state). Describe the pipeline as built on
a swappable matcher with the current decision behavior you confirmed — remove the
contradiction with the advisory-caveat line. Keep the wording honest and specific
(e.g. name the model, state whether it currently decides or is advisory).

**Verify**: re-read both lines; they no longer contradict the advisory-caveat line.

### Step 3: Update the roadmap status

In `docs/contactless-fingerprint-roadmap.md`, correct the stale rows:
- mobile hand-capture UI: change from "blocked" to its real state (screen exists
  and is routed; note any remaining capture-UX gaps you can verify, e.g. framing
  overlay / per-finger quality gating, but only if you confirm them in the code).
- ONNX embedding matcher: change from "scaffolded, inactive" to reflect that the
  model file and threshold plumbing exist; describe the actual current decision
  behavior.

**Verify**: the roadmap's "Remaining before a real contactless demo" list matches
what is actually left, per your code reads.

### Step 4: Refresh CLAUDE.md

Update `CLAUDE.md` tech-stack and core-features sections to describe the real
system: FastAPI biometric microservice, four-finger contactless hand pipeline with
ONNX Ridgeformer embedding + score fusion, InsightFace/FAISS face recognition, the
multimodal (face-shortlist → fingerprint-confirm) decision flow with thresholds in
Laravel, Sanctum auth, hospital multi-tenancy, and the advisory-until-calibrated
contactless policy. Keep the existing "avoid overengineering / MVP-first" ethos.

**Verify**: `grep -in "flask\|opencv" CLAUDE.md` → returns nothing that describes
the stack as Flask/OpenCV-only (OpenCV may still be mentioned as a preprocessing
lib, but not as the whole AI stack).

## Test plan

- No automated tests (docs only). If Mintlify CLI is available, `mint dev` should
  build with no broken-nav warnings after Step 1.

## Done criteria

ALL must hold:

- [ ] `docs/mint.json` deleted; `docs/docs.json` is valid JSON and the sole config.
- [ ] README's contactless description no longer contradicts its own advisory caveat.
- [ ] Roadmap status rows for hand-capture UI and ONNX matcher reflect the verified code state.
- [ ] `CLAUDE.md` describes the four-finger + face + multimodal system, not a Flask/OpenCV single-finger prototype.
- [ ] No code files modified (`git status` shows only docs/CLAUDE.md changes).
- [ ] `plans/README.md` status row for 010 updated.

## STOP conditions

Stop and report back if:
- `docs.json` turns out NOT to be the canonical config (e.g. the build script
  explicitly references `mint.json`) — do not delete anything; report which is live.
- Reading `VerificationController` shows `verify/hand` behavior you can't
  confidently characterize — describe it as "advisory/deciding per the registered
  matcher" and flag the ambiguity rather than overstating.

## Maintenance notes

- Keep a single Mintlify config going forward; a stray `mint.json` reappearing is
  the drift to watch in review.
- When plan 002 lands (pipeline repair) and plan 011 (FAISS shortlist), revisit the
  roadmap so it keeps tracking reality.
- Reviewer should spot-check that no doc now claims a capability the code lacks.
