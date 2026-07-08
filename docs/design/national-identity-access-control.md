# Design: National patient identity + separate access-control layer

Companion to `docs/adr/013-national-patient-identity.md` (read the ADR first —
it holds the decision, alternatives, and the two flagged decision-point
resolutions this doc builds on). This doc covers the entity model, the
identity/access API shapes, national-scale FAR, and the migration outline.

## Step 1: Target domain model

### Entities

```
                    ┌───────────────────────────┐
                    │  Patient (NATIONAL)       │
                    │  id (national patient id) │
                    │  nida (nullable, unique)  │
                    │  full_name, dob, gender,  │
                    │  phone, notes             │
                    └─────────────┬─────────────┘
                                  │ 1
                    ┌─────────────┼─────────────────────────┐
                    │ N           │ N                       │ N
        ┌───────────▼──────┐ ┌────▼─────────────┐  ┌────────▼──────────┐
        │ FaceTemplate      │ │ Fingerprint       │  │ PatientHospitalLink│
        │ (NATIONAL,        │ │ (NATIONAL,        │  │ (LINK — provenance)│
        │  enrolled_by FK   │ │  enrolled_by FK    │  │  patient_id FK     │
        │  hospital_id =    │ │  hospital_id =     │  │  hospital_id FK    │
        │  enrolling site,  │ │  enrolling site,   │  │  first_seen_at     │
        │  provenance not   │ │  provenance not    │  │  relationship_type │
        │  ownership)       │ │  ownership)        │  │  (enrolled/referred│
        └───────────────────┘ └────────────────────┘  │  /visited)         │
                                                        └─────────────────────┘
                    │ 1
        ┌───────────▼──────────────┐
        │ Visit (HOSPITAL-OWNED)   │
        │  hospital_id FK          │
        │  patient_id FK (national)│
        │  opened_by/closed_by     │
        └───────────┬──────────────┘
                    │ 1
        ┌───────────▼──────────────┐
        │ VisitStage (HOSPITAL)    │
        │  visit_id FK             │
        │  verification_log_id FK  │
        └───────────────────────────┘
```

This is the OpenHIE CR/SHR split applied to our schema: `Patient` +
`FaceTemplate`/`Fingerprint` (identity/biometric layer) become national;
`Visit`/`VisitStage` (clinical activity layer) stay hospital-owned, keyed by
`(patient_id, hospital_id)`. `PatientHospitalLink` is our `MPI_Local_Link`
equivalent — it records *which hospitals have a relationship with this
patient* for authorization purposes, without implying ownership.

### Per-table disposition

| Table | Today | Target | Why |
|---|---|---|---|
| `patients` | hospital-scoped (`hospital_id` FK, cascade delete) | **National** | This is the identity record CR/MPI research grounds — one row per real person, no single owning hospital. |
| `face_templates` | hospital-scoped | **National**, `hospital_id` becomes *enrolling-site provenance* | Face FAISS index is already a single global gallery (`python-service/app/services/faiss_service.py`); the Laravel `hospital_id` column already doesn't gate the underlying search, only the interim access filter plan 005 relocates. |
| `fingerprints` | hospital-scoped (`hospital_id` denormalised for query perf per its own migration comment) | **National**, `hospital_id` becomes *enrolling-site provenance* | Same reasoning; plan 005 already drops the `loadCandidateHands` hospital pre-filter. Keep the denormalised column (perf), change its *meaning*. |
| `patient_hospital_links` (new) | doesn't exist | **New link table** | Our `MPI_Local_Link` analogue: `(patient_id, hospital_id, first_seen_at, relationship_type)`. Populated on enrollment and on any visit at a hospital that hasn't seen this patient before. This is the input `PatientAccessService` consults post-ADR (see Step 2/3). |
| `visits` | hospital-scoped (`hospital_id` FK) + `patient_id` FK | **Hospital-owned, unchanged shape** | This is exactly the "clinical activity" layer the ADR says stays hospital-owned — a visit is an encounter a specific hospital had with a national patient. `hospital_id` here already means ownership correctly; no semantic change needed. |
| `visit_stages` | keyed by `visit_id` only (no direct `hospital_id`) | **Hospital-owned, unchanged** | Inherits hospital ownership transitively through `visits`. |
| `verification_logs` | referenced by `visit_stages.verification_log_id` | **Hospital-owned, unchanged** | Same — a verification event happened at a specific hospital's terminal. |
| `patient_edit_requests` | hospital-scoped (`hospital_id` FK) + `patient_id` FK | **Hospital-owned, unchanged** | An edit request is *raised by* a specific hospital's staff about a national patient's demographic data; approval workflow stays hospital-scoped (a nurse at Hospital B shouldn't approve a correction requested at Hospital A). Cross-hospital edit conflicts are an explicit out-of-scope item for the future build plan, not this design. |
| `audit_logs` | `staff_id`, `patient_id` (nullable), `hospital_id` | **Unchanged, and becomes MORE load-bearing** | This is exactly the mandatory audit trail the ADR's decision 1 (`access_restricted`) depends on — every denial with the identified patient id but no PII already fits this table's existing shape. No migration needed here; this table is why the access decision is safe to make more conservative. |
| `hospitals` | — | **Unchanged** | Still the facility registry; unaffected by patient ownership. |
| `supervisor_overrides` | (not inspected in detail — hospital-scoped per existing convention) | **Hospital-owned** | An override is an action a specific hospital's supervisor took; no identity implication. |

## Step 2: The identity layer ("our Client Registry / MPI")

### Resolution API

```
IdentityResolver::resolve(BiometricProbe $probe): IdentityResult

BiometricProbe:
  - face_embedding?: float[]
  - hand_embedding?: float[]        // four-finger, per four-finger-and-verification-architecture
  - nida?: string                   // optional deterministic anchor

IdentityResult:
  - status: 'matched' | 'needs_review' | 'no_match'
  - patient_id: int|null            // NATIONAL patient id — never hospital-scoped
  - confidence: float
  - matched_via: 'face' | 'hand' | 'multimodal_confirm'
```

This is exactly what plan 005 already builds into `FaceController`/
`VerificationController` — this design doesn't introduce a new resolver, it
names the contract those two call sites already converge on so a future
refactor can extract it into one shared class instead of two parallel
implementations.

**NIDA anchor seam**: when `nida` is present on the probe (e.g. captured at
kiosk check-in, or entered by clerk), it deterministically narrows the
candidate set *before* biometric scoring — `WHERE patients.nida = ?` first;
biometric confirms the identity claim rather than searching the full gallery.
When absent (the common pilot case — Tanzania's e-ID/NIDA coverage is
partial), fall back to the existing 1:N biometric search across the whole
national gallery. This mirrors the research finding that the NIN is the
deterministic anchor and biometrics are the probabilistic layer, not a
replacement for it.

### Deduplication on enrollment (MPI duplicate check)

Before `PatientController::enroll*` creates a new `patients` row:
1. Run the same `IdentityResolver::resolve` the verify paths use, on the new
   enrollment's captured biometric.
2. **Above the identify threshold** → do NOT create a new patient; this is
   the same person re-enrolling (possibly at a new hospital) — create a
   `patient_hospital_links` row for this hospital instead, and (if biometric
   quality is higher) optionally refresh the stored template.
3. **Borderline** (between `needs_review` and `matched` thresholds) → do not
   auto-merge. Queue for **human adjudication** — an admin reviews both
   records side by side and either confirms "same person" (merge into
   `patient_hospital_links`) or "different person" (proceed with new
   enrollment). This is the same adjudication-queue pattern CR/MPI
   implementations use for probabilistic (Fellegi-Sunter-style) matching.
4. **Below both thresholds** → proceed with new enrollment as today, then
   write the initial `patient_hospital_links` row.

Building the adjudication queue UI/workflow is explicitly deferred to the
future build plan (see Migration outline, Step 6) — this design only defines
where it plugs in.

## Step 3: The access-control layer ("our IOL / consent")

### Authorization flow

```
1. Operator authenticates (Sanctum, existing).
2. IdentityResolver::resolve() → national patient_id (Step 2).
3. PatientAccessService::authorizePatientAccess(User $operator, Patient $patient): AccessDecision
     - checks patient_hospital_links for a row linking $operator->hospital_id
       to $patient (i.e. "has my hospital ever enrolled or seen this patient")
     - OR $operator->isSuperAdmin()
     - OR (phase 2) an active consent/referral grant
     - OR (phase 2) an active break-glass override
4. Allowed  → 'matched', full record, audit(match).
   Denied   → 'access_restricted', NO PII, audit(denied, patient_id=X) — per ADR decision 1.
```

Plan 005 already ships steps 1–4 with a same-hospital-only check inside
`PatientAccessService`; this design's only change to that service is *what it
consults* (`patient_hospital_links` instead of `hospital_id` equality) — the
method signature `(User, Patient): bool` (or a small result/enum, per plan
005's own note) does not change, so plan 005's callers need no further edits
when this design's migration lands.

### Minimal computable consent (phase 2, not built in this spike)

Tuple: `(patient_id, grantee_hospital_id | grantee_role, access_scope,
status, granted_at, expires_at)`. `access_scope` starts coarse (`full_record`
vs `none`) — DS4P-style section tagging (mental health, reproductive health,
substance use) is a later refinement once the coarse grant model is proven,
not a pilot requirement.

**Decision point 3 (opt-in vs opt-out) — recommendation**: **opt-in for the
pilot.** A patient's records are visible to (a) any hospital in their
`patient_hospital_links` (they were physically seen there — implied consent
from the encounter itself) and (b) nowhere else, until an explicit referral or
consent grant exists. This needs no patient-facing UI to build for the pilot —
it falls directly out of the link table already required for access-control —
and it is the more conservative default, consistent with decision 1's
existence-disclosure caution. Opt-out (default-open, patient must actively
restrict) is a heavier governance commitment (needs a patient-facing consent
UI/channel) that the pilot doesn't need yet; revisit once referral flows are
real.

### Break-glass (phase 2, shape only)

Minimal shape: `BreakGlassRequest(operator, patient, justification: string,
expires_in: duration)` → grants temporary access, forces
`audit_logs` entry `ACTION_BREAK_GLASS` (new constant, alongside the existing
`ACTION_*` list in `AuditLog.php`) with the justification text, and triggers a
notification to the patient's linked hospitals + a super-admin. No workflow
UI in this spike — this is intentionally deferred; a pilot without referral
volume has limited break-glass need, but the shape should exist in the ADR so
it isn't bolted on awkwardly later.

**Decision point 4 (NIDA integration depth) — recommendation**: **design the
seam only, no mock service, for this spike.** The resolution API above
(Step 2) already has an optional `nida` field wired through; that is the seam.
Building even a mock NIDA HTTP client is real integration work (auth, request
shape, error handling) that has no payoff until a build plan actually
implements enrollment-time NIDA capture — building a mock now risks the mock's
assumptions (fields, response shape) diverging from the real NIDA API/HOMIS
mock effort and having to be redone. Coordinate with whoever owns the HOMIS
mock idea before either team builds a NIDA/HOMIS stub, so there's one mock, not
two independently-guessed ones.

## Step 4: FAR at national gallery scale

Today's thresholds (face `IDENTIFY_THRESHOLD`, contactless hand fusion
threshold 57.5 per `fingerprint_calibration_session_progress.md`) were tuned
against a **hospital-sized** gallery. A national gallery is orders of
magnitude larger, and 1:N false-accept rate scales with gallery size for a
fixed per-comparison FAR — the same reasoning already flagged in
`diagnosis_weak_points_2026_06.md` ("1:N FAR scaling").

Mitigations, in order of how much they buy:
1. **NIDA anchor (Step 2)** — when present, collapses the search space from
   "whole national gallery" to "candidates matching this NIN," which restores
   an effectively hospital-sized (or smaller) 1:N comparison set. This is the
   single biggest lever and the reason the research repeatedly calls the NIN
   "deterministic" versus biometrics being merely "probabilistic."
2. **Multimodal confirm** — face candidate above threshold confirmed by
   four-finger hand embedding (or vice versa) before `matched`, per
   `four_finger_and_verification_architecture.md`. This is already the
   direction the system is moving (Ridgeformer embedding, 6-8% EER) and
   compounds with the anchor: NIN narrows the pool, multimodal confirms the
   specific candidate.
3. **Tighter operating point without an anchor** — for the fallback
   (biometric-only) path, the *national* gallery needs a stricter threshold
   than the *hospital* gallery to hold the same absolute FAR, since FAR
   compounds across more comparisons. This spike does not re-derive the
   national threshold value (that's a calibration exercise, not a design
   decision) — it records that the *same* threshold value used today is
   **not** automatically safe once the gallery goes national, and flags
   re-calibration as a required step before this design's identity-resolution
   change ships to more than a pilot-sized gallery.

## Step 5: Migration outline (NOT applied in this spike)

Ordered, reversible, backfillable. Each step is additive until the final
cutover; every step before the cutover can be rolled back by dropping the new
column/table without touching existing behavior.

1. **Add `patient_hospital_links` table** (new, empty). No behavior change —
   nothing reads it yet.
   ```
   patient_hospital_links: id, patient_id FK, hospital_id FK,
     first_seen_at, relationship_type enum('enrolled','visited','referred'),
     created_at
   unique (patient_id, hospital_id)
   ```
2. **Backfill**: for every existing `patients` row, insert one
   `patient_hospital_links` row `(patient_id, patients.hospital_id,
   patients.created_at, 'enrolled')`. This captures 100% of today's implicit
   ownership as explicit provenance — no information is lost, no behavior
   changes yet (nothing reads the table).
3. **Cross-hospital duplicate detection (offline, read-only)**: run
   `IdentityResolver::resolve` (Step 2) against every enrolled biometric
   template as a batch job, looking for patients enrolled independently at
   two+ hospitals who are actually the same person. Produce a report; do NOT
   auto-merge. This surfaces the actual scale of the duplicate problem before
   committing to a merge strategy.
4. **Human adjudication of the duplicate report** (Step 3's output): for each
   flagged pair, an admin confirms merge or rejects. A confirmed merge:
   consolidate `fingerprints`/`face_templates` under the surviving
   `patient_id`, insert `patient_hospital_links` rows for both hospitals under
   the surviving patient, soft-delete (do not hard-delete — keep for audit)
   the duplicate `patients` row with a `merged_into_patient_id` pointer.
5. **Switch `PatientAccessService::authorizePatientAccess`** to consult
   `patient_hospital_links` instead of `patient.hospital_id ===
   operator.hospital_id`. Ship behind a config flag (`config('access.national_link_check')`,
   default off) so it can be toggled without a deploy; verify against the
   plan-005 test suite (`FaceVerifyAccessControlTest`,
   `HandVerifyAccessControlTest`, `PatientAccessServiceTest`) with the flag on
   in CI before flipping the default.
6. **Only after step 5 is proven in production**: stop treating
   `patients.hospital_id` as an authorization field in any remaining call site
   (re-audit `PatientPolicy`, `FingerprintPolicy`, and any report/export query
   that filters by `patient.hospital_id` for access reasons — see grep list
   below). `patients.hospital_id` itself can remain as a "which hospital
   originally enrolled this patient" historical field (equivalent to
   `patient_hospital_links`'s first row) or be dropped once fully redundant —
   that call is a later cleanup, not required for correctness.

**Rollback at any point before step 6**: drop `patient_hospital_links`,
revert `PatientAccessService` to the `hospital_id` equality check. No data was
mutated on `patients`/`fingerprints`/`face_templates` until step 6, so rollback
is a pure code revert.

**Known re-audit list for step 6** (found via
`grep -rn "hospital_id" laravel/app/Policies laravel/app/Http/Controllers/Api`
during this spike — re-run before executing step 6, this list will drift):
`PatientPolicy::view/update/delete/enroll/removeFingerprint`,
`FingerprintPolicy::unlock/delete`, `FaceController::interpretCandidate` (line
~444, superseded by plan 005 already), `VerificationController` patient-list
filtering (~lines 567–573) and audit-log scoping (~line 604).

## Done-criteria cross-check

- [x] Entity model + per-table disposition — Step 1 above.
- [x] Identity resolution API + dedup rule + adjudication fallback — Step 2.
- [x] Authorization flow + pilot consent/break-glass scope — Step 3.
- [x] FAR-at-scale rationale + mitigation — Step 4.
- [x] Migration outline, ordered/reversible, not applied — Step 5.
- [x] All four decision points surfaced with a recommendation (1 & 2 in the
      ADR; 3 & 4 above) — awaiting sign-off.
