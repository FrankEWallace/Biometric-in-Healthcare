---
date: 2026-06-05
topic: "Multi-capture (gallery-of-3) fingerprint enrollment with face fallback"
outcome: "Build a 3-template-per-finger gallery with Max-Rule matching, auto-triggered single-session capture, face fallback for weak fingers, and an is_gallery_lead flag keeping 1:N identification one-template-per-finger; fingerprint-only scope this iteration."
---

# Grill Session: Multi-Capture Fingerprint Enrollment

## Context

Goal: improve biometric enrollment accuracy for the FYP patient-ID system (Flutter + Laravel + Python/OpenCV). Starting point already on branch `feature/touchless-autotrigger-ios-compat`:
- Auto-trigger capture exists (`fingerprint_liveness_camera_screen.dart`): streams frames, sharpness gate (variance ≥ 300), fires after 3 consecutive sharp frames, locks focus/exposure.
- 6-frame optical-flow liveness exists (`liveness_service.py`, `FingerprintService::livenessCheck`).
- Minutiae matcher in pure Python/OpenCV behind a SourceAFIS-compatible interface (`sourceafis_service.py` → `minutiae_service.py`); real SourceAFIS is NOT installed and is not pip-installable.
- `verifyAgainstAll` already implements Max-Rule (best candidate score vs `MATCH_THRESHOLD`).
- 1:N hospital-wide scan is two-tier (primary fingers first, then non-primary) — `VerificationController.php`.
- `quality_score` column already exists on fingerprints; `unique(patient_id, finger_position)` constraint currently allows only 1 template per finger.
- Registration flow already sequences: form → fingerprint → face (face skippable / non-fatal).

## Q&A

1. **Q:** Storage model — best-of-N (store 1) vs. a group of uploads (gallery)? Which is better for accuracy?
   **A:** Gallery of 3 for fingerprint. (Research: gallery/fusion beats best-of-N; EER 0.16% vs ~1.12%. Fusion-by-averaging only valid for fixed-length embeddings like face, NOT for minutiae — so fingerprint uses a gallery, not a merged template.)

2. **Q:** Touch-ID-style minutiae mosaicking/stitching into one rich template — attempt it, or use a gallery?
   **A:** Gallery of 3. Mosaicking needs contactless pose alignment (ellipsoid model + RANSAC) at enroll time and can corrupt the template; a gallery lets the matcher (SourceAFIS interface) align per-template at match time instead. Mosaicking is out of scope.

3. **Q:** Matcher backend — keep native Python minutiae matcher and ship gallery first, or stand up a JVM SourceAFIS sidecar now?
   **A:** A — keep the native matcher, ship gallery-of-3 first; only add a SourceAFIS JVM sidecar later if FAR/FRR proves it necessary. (Interface is already abstracted, so the swap stays reversible.)

4. **Q:** Capture UX — 3 fully-automatic captures in one session, or 3 discrete manual rounds? Enforce the reposition hint?
   **A:** Automatic single session with an advisory (NOT enforced) reposition hint between shots.

5. **Q:** Partial-capture failure — and the case where fingerprint fails AND the hospital has face disabled.
   **A:** (b) Never block. Try for 3 → floor of 1 if the finger is weak → if fingerprint fails and face is disabled, enroll a degraded 1-sample fingerprint and store a `needs_reenrollment` flag. (Do NOT override the hospital-wide face toggle for one patient.) When face IS enabled, a 0-capture finger falls back to face as primary biometric.

6. **Q:** Threshold & 1:N — the gallery triples the candidate pool and inflates FAR/latency. How to handle?
   **A:** (c) + (a): use the full 3-gallery for 1:1 verification, keep 1:N identification one-template-per-finger, then recalibrate `MATCH_THRESHOLD` from a fresh FAR/FRR measurement rather than guessing.

7. **Q:** How to designate the single 1:N representative template once a finger has 3?
   **A:** (a) Add boolean `is_gallery_lead` — exactly one true per (patient, finger_position), set to the max-`quality_score` capture. 1:N filters `WHERE is_gallery_lead = true` (then existing is_primary tiering); 1:1 `verifyAgainstAll` ignores it and uses all 3.

8. **Q:** Liveness for a 3-capture session — once per session or before each capture?
   **A:** (a) Once per session; the single verdict gates all 3 captures. (Supervised hospital setting; mid-session spoof-swap is out of threat model.)

9. **Q:** Upload contract & where `is_gallery_lead` is decided — reuse endpoint 3× or batched per-finger endpoint?
   **A:** (b) Batched per-finger endpoint: accepts up to 3 captures + the session liveness verdict, processes each via `/process`, stores rows, and atomically sets `is_gallery_lead` to the max-`quality_score` capture in one transaction (handles floor-of-1 and `needs_reenrollment` in one place).

10. **Q:** Scope & sequencing — fingerprint gallery only, both face+fingerprint, or face fusion first?
    **A:** (a) Fingerprint gallery-of-3 only this iteration. Face embedding-averaging fusion is a separate later work item (keeps the FAR/FRR before-after measurement clean).

## Key Decisions

- **Fingerprint enrollment = gallery of 3 templates per finger** (not best-of-N, not minutiae mosaicking).
- **Matcher stays the native Python/OpenCV minutiae implementation**; real SourceAFIS (JVM sidecar) deferred until FAR/FRR proves it needed. JVM costs that justify deferral: 4th runtime, ~150–300 MB idle RAM, 1–3 s cold start, JDK in build, extra IPC + ops surface.
- **Capture = one automatic session, 3 auto-triggered shots**, advisory non-enforced reposition hint between shots; reuses existing auto-trigger (3 consecutive sharp frames, variance ≥ 300).
- **Liveness runs once per session** (6-frame optical flow) and gates all 3 captures.
- **Never block enrollment:** try 3 → floor 1 → if fingerprint fails with face disabled, store degraded 1-sample fingerprint + `needs_reenrollment` flag; if face enabled, fall back to face as primary. The existing registration flow already sequences fingerprint → face.
- **Schema:** drop `unique(patient_id, finger_position)`; add boolean `is_gallery_lead` (one true per finger, = max `quality_score`); back-fill `is_gallery_lead = true` for all existing single-template rows. `quality_score` column already exists.
- **Matching:** 1:1 `verifyAgainstAll` uses all 3 templates (Max-Rule, already implemented); 1:N identification (both tiers) filters `is_gallery_lead = true` to stay one-template-per-finger.
- **Threshold:** keep `MATCH_THRESHOLD` for now, then recalibrate from a fresh FAR/FRR run after the gallery ships (do not tune blind).
- **Upload:** new batched per-finger endpoint receives 3 captures + session liveness verdict; server scores each via `/process`, stores rows, atomically sets `is_gallery_lead`, applies floor-of-1/`needs_reenrollment`.
- **Scope this iteration: fingerprint only.** Face embedding-averaging fusion (5–10 samples → averaged master template) is a separate future work item.

## Implementation Notes (not decisions, surfaced during grilling)

- Research notebook created in NotebookLM: "Biometric Patient ID: Auto-Trigger Fingerprint + Face Capture" (30 sources) — usable for an FYP write-up/report/podcast.
- Dropping a UNIQUE constraint on SQLite (the test DB) requires a table rebuild; verify the migration runs on both MySQL and SQLite (recent commits already address SQLite test compatibility).
- `is_primary` (per-patient primary finger, drives 1:N tiering) and `is_gallery_lead` (per-finger best template) are orthogonal — keep both.

## Open Questions

- None. Decision tree fully resolved for the fingerprint gallery-of-3 work item. (Face embedding-averaging fusion deferred to its own session.)
