# ADR-013: National patient identity, hospital-scoped clinical records

- **Status**: Accepted — both decision points signed off by the maintainer on 2026-07-10 (recommendations adopted as written: expose `access_restricted`; National Patient + Hospital Record)
- **Date**: 2026-07-08
- **Driven by**: `plans/013-national-patient-identity-spike.md`
- **Supersedes/enriches**: the access-control seam introduced by `plans/005-face-identify-topk-hospital-filter.md`
- **Research basis**: NotebookLM notebook `1fff992a-41e2-4bb2-97e4-f996a4ff5d41` ("National Patient Identity Architecture — Biometric Healthcare (NHIF/NIDA scale)"), 20 sources incl. the OpenHIE Architecture Specification v3.0, OpenHIE Client Registry spec, Tanzania National Health Client Registry concept note, Tanzania Digital Health Strategy, and a federated-MPI academic case study (CDHMS)

## Context

The system today is **hospital-partitioned**: `patients.hospital_id`,
`face_templates.hospital_id`, `fingerprints.hospital_id` all scope a patient's
identity to the hospital that enrolled them. The actual boundary enforcement
lives in `App\Policies\PatientPolicy` / `FingerprintPolicy` (404 on
cross-hospital access) — **not**, as earlier framing assumed, in the
`hospital.access` middleware alias, which resolves to
`CheckHospitalAccess` (`laravel/app/Http/Middleware/CheckHospitalAccess.php`),
an IP/CIDR geofence unrelated to patient ownership. This ADR corrects that
conflation; the migration in Step 5 below targets the policies and the
`FaceController`/`VerificationController` identity-resolution code, not the
geofence middleware.

Real patient journeys cross hospitals: register at A, seen at B while
travelling, referred to C, treated at D. Hospital-owned identity causes
duplicate registrations, duplicate biometric templates, fragmented histories,
and insurance-verification friction — this is the core problem plan 005
already patches at the seam level (`PatientAccessService`) and this ADR
resolves at the model level.

## Decision

Adopt the **OpenHIE Client Registry / Interoperability Layer (CR/IOL) pattern**:

1. **Identity is national.** A patient has exactly one national identity,
   independent of which hospital first registered them. The biometric engine
   (face FAISS index, four-finger embedding matcher) answers *"who is this
   person?"* against the whole national gallery, never a hospital-scoped
   subset.
2. **Clinical activity is hospital-owned.** Visits, admissions, diagnoses, lab
   results, prescriptions, and billing belong to the hospital that produced
   them, and reference the national identity by foreign key. Hospitals do not
   own the *patient*; they own their own *encounters* with that patient.
3. **Access is a separate, audited decision made after identity resolves.**
   Resolving identity must never, by itself, grant access to another
   hospital's records. `PatientAccessService::authorizePatientAccess` (plan
   005) is the single seam this decision grows through — it will gain
   consent/referral/break-glass logic without any change to the biometric
   controllers.

This is not a novel design: it is the same split OpenHIE assigns to the
**Client Registry** (identity, probabilistic + deterministic matching) versus
the **Shared Health Record** (clinical events), connected through an
**Interoperability Layer** that resolves local↔global identifiers per facility.
Tanzania's own National Health Client Registry concept note describes the
identical goal for GoT-HoMIS/AfyaCare facility systems, and a federated-MPI
case study (CDHMS) documents the concrete relational shape: a global patient
table, an `MPI_Local_Link` mapping global ID → facility `Node_ID`, and
encounter tables that carry a `Patient_ID` foreign key plus a `Node_ID`
recording which facility owns that specific record — never patient
demographics duplicated per facility.

## Alternatives considered

| Option | Description | Rejected because |
|---|---|---|
| **A — Status quo (hospital-owned patient)** | Keep `patients.hospital_id` as the identity boundary; biometric search stays hospital-scoped or is patched with ad-hoc cross-hospital exceptions. | Doesn't fix duplicate enrollments/templates or fragmented histories; the FAISS face index is already a global gallery in practice, so hospital-scoping identity is already fictional for face and only true for hand because of an explicit pre-filter (plan 005 removes that pre-filter regardless). Continuing to model identity as hospital-owned fights the direction the code is already moving. |
| **B — Fully open cross-hospital records (no access layer)** | National identity **and** any authenticated hospital operator can read any patient's full record. | Correct on identity, wrong on access — this is the opposite failure mode (over-disclosure) and is explicitly the option this ADR's access-layer requirement rules out. Not appropriate for an NHIF-scale system without consent/referral machinery. |
| **C — National identity + hospital-gated access + mandatory audit (CHOSEN)** | Identity resolves nationally; a **separate, audited** access-control step (`PatientAccessService`) decides what a querying hospital may see; cross-hospital hits are `access_restricted`, never a fake `no_match`. Consent/referral machinery is phase 2 (this spike only designs the seam). | Matches the OpenHIE/Tanzania CR precedent, doesn't require building the full consent engine before the identity fix ships, and keeps the boundary auditable and reversible (Section "Migration outline" in the design doc). |

Option C is the decision. Full detail (per-table disposition, resolution API,
migration outline) is in
`docs/design/national-identity-access-control.md`.

## Decision points (both SIGNED OFF 2026-07-10 — recommendations below are now decisions)

### 1. Does a cross-hospital hit tell the client `access_restricted`, or is that suppressed to `no_match` externally?

**Research finding**: this exact tension is documented, not hypothetical.
Clinicians and HIE researchers argue that returning a generic "not found" when
a record actually exists is *itself* a documented failure mode — some
production EHR integrations (cited in the research as an Epic-configuration
pattern) default to "Patient not Found" under a consent restriction, and policy
reviewers call this "inaccurate" and "counter-productive to continuity of
care," because it hides from the clinician that more information exists to be
sought via direct patient consent. Conversely, disclosing that a patient
*exists* in the registry is its own information leak (confirms program/status
membership) — this is the real risk for a public-figure/journalist-probe
scenario.

OpenHIE's own Care Services Discovery workflow resolves this by **not**
merging the two failure modes: an authorization failure returns an explicit
**"invalid access"/"invalid authorization" error**, distinct from a
not-found result for an identity that doesn't resolve at all.

**Recommendation: expose `access_restricted` to the client, never fold it into
`no_match`.** Concretely:
- The **existence-disclosure risk is bounded, not eliminated, by scope**: only
  authenticated hospital operators can trigger a lookup at all (this is not a
  public-internet existence oracle) — the geofence + Sanctum auth already gate
  who can query. The residual risk is an authenticated-but-unauthorized
  operator at Hospital B learning that a specific person is a patient
  somewhere in the national system.
- That residual risk is the smaller failure mode versus the clinical-safety
  cost of a silent `no_match`: a nurse at Hospital B who is told `no_match` may
  re-enroll the patient as new (recreating the duplicate-identity problem this
  whole ADR exists to solve) or treat them as having no prior history, exactly
  the outcome the research flags as unsafe.
- `access_restricted` carries **zero PII** — no name, no demographics, no
  clinical data — only the fact of a denial. This mirrors OpenHIE's
  "invalid access" response, which signals a rights problem without leaking
  the record.
- The denial is always written to an audit log **with the resolved patient
  id**, so an abuse pattern (operator repeatedly probing for a specific
  person) is detectable after the fact even though it isn't blocked in the
  moment. Phase 2 (consent engine, this spike's Step 3) can add rate-limiting
  or anomaly detection on repeated `access_restricted` results if this becomes
  a real threat in practice.

This resolves the plan-005 STOP condition: `access_restricted` is not a
governance-neutral fallback, it is the recommended posture.

### 2. Is `patient->hospital_id` the right authorization basis, or does the model become National Patient + Hospital Record?

**Recommendation: National Patient + Hospital Record.** This is the
architecture already described in Decision 1–2 above and is directly precedented
(OpenHIE CR/SHR split; Tanzania CR; the CDHMS global-ID + `MPI_Local_Link` +
`Node_ID`-tagged-encounter relational pattern). Concretely:

- `patients` becomes the **national identity table**: one row per real person,
  no `hospital_id` column as an ownership/authorization field.
- A new **facility-registration / local-link** concept records *which
  hospital(s) a patient has been seen at* — this is provenance and an
  authorization input, not ownership. (Modeled as `patient_hospital_links` in
  the design doc, analogous to CDHMS's `MPI_Local_Link`.)
- Every hospital-scoped table that today means "this patient belongs to my
  hospital" (visits, fingerprints, face templates as *enrollment* records)
  gets re-read as "this hospital produced/holds this record about this
  national patient" — the foreign key to `patients` stays, the *meaning* of
  `hospital_id` on those tables shifts from ownership to provenance/access
  scope.
- `PatientAccessService::authorizePatientAccess` becomes: "has this hospital
  ever been linked to this patient (via `patient_hospital_links`, i.e. an
  enrollment or a visit), or does the operator hold a broader grant (referral,
  consent, super-admin, break-glass)?" — not "does `patient.hospital_id`
  equal `operator.hospital_id`."

This is the deeper reason plan 005's `PatientAccessService` signature is
`(User $operator, Patient $patient)` and not `(Patient $patient, int
$hospitalId)`: the generic signature is what lets this ADR's model land later
without touching the biometric controllers again.

## Consequences

- **Positive**: no more duplicate registrations/templates across hospitals;
  cross-hospital identity is finally true instead of accidentally true (face)
  or false (hand, pre-005); one auditable access decision point instead of
  scattered `hospital_id ===` checks in policies and controllers; matches a
  well-precedented reference architecture instead of an ad-hoc scheme.
- **Negative / costs**: the hand-verify path becomes an O(N_national) linear
  scan until plan 011 ships FAISS shortlisting (already flagged as an
  Interactions/STOP item in plan 005); every place that currently reads
  `patient.hospital_id` as an authorization check must be re-audited (policies,
  controllers, any report/export queries) — missing one is a silent
  regression back to the wrong model; national-scale FAR requires the NIDA
  anchor + multimodal confirm (design doc Step 4) or accuracy degrades as the
  gallery grows.
- **Reversibility**: the migration outline (design doc) is written as ordered,
  additive, backfillable steps — `hospital_id` is not dropped until the new
  authorization path is proven in production; a rollback can restore the old
  policy check without a data migration.

## Sequencing

1. **Plan 005** (independent, ships first): introduces
   `PatientAccessService::authorizePatientAccess(User, Patient)` and makes both
   biometric paths resolve identity nationally, today still gated by
   `patient.hospital_id === operator.hospital_id` inside the service body.
2. **This ADR** (accepted here): defines the target data model and the
   decision-point resolutions above. Unblocks:
3. **A future build plan** (not this spike): executes the migration outline —
   introduces `patient_hospital_links`, rewrites
   `PatientAccessService::authorizePatientAccess` to consult it instead of
   `hospital_id` equality, backfills existing data, re-audits every
   `hospital_id`-as-authorization call site listed in the design doc.
4. **Plan 013's own optional Step 6** (this spike): may prototype the
   read-only national identity-resolution seam behind a flag, but changes no
   write path, no tenancy, and no live authorization behavior.
5. **Consent/referral/break-glass engine** (phase 2, separate plan): grows
   out of the `PatientAccessService` seam once the National Patient + Hospital
   Record model (point 2 above) is in place.

## STOP / guardrails carried over from the spike plan

- Do not remove `patients.hospital_id` or any policy check before the
  replacement authorization path (`patient_hospital_links` +
  `PatientAccessService`) exists and is tested.
- Do not touch `CheckHospitalAccess` (`hospital.access` middleware) as part of
  this work — it is an unrelated network geofence, not the ownership boundary.
- The full migration is out of scope for this spike; see
  `docs/design/national-identity-access-control.md` for the outline a later
  build plan executes.

## References

- OpenHIE Architecture Specification v3.0 — Client Registry / Shared Health
  Record separation of concerns.
- OpenHIE Client Registry architecture spec — CR workflow requirements.
- Tanzania National Health Client Registry concept note — facility
  registration linking, NIDA anchor, "seen at a new facility" scenario.
- Tanzania Digital Health Strategy / GOVESB — Health Information Mediator,
  GoT-HoMIS/AfyaCare facility silo problem this ADR solves nationally.
- CDHMS federated-MPI case study — `MPI_Local_Link`/`MPI_Remote_Link`,
  `Node_ID`-tagged encounter table, break-glass/RBAC/ABAC keywords.
- IHE / OpenHIE Care Services Discovery workflow — "invalid access" vs.
  not-found response distinction.
