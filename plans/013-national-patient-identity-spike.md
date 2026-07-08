# Plan 013: Design spike — national patient identity + separate access-control layer

> **Executor instructions**: This is a DESIGN / SPIKE plan, not a build-everything
> plan. The deliverable is a written design document plus a schema-migration
> outline and a prototype of the smallest slice — NOT a full national identity
> platform. Investigate, define the interfaces, list the open questions, and STOP
> at the decision points marked below rather than building past them. When done,
> update the status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/app/Models laravel/database/migrations laravel/app/Http/Middleware laravel/app/Policies`
> If the tenancy/model files changed materially, re-read them before designing.

## Status

- **Priority**: P2 (direction — do before any code that assumes hospital-owned patients)
- **Effort**: L (spike; the full build is much larger and is explicitly deferred)
- **Risk**: MED (touches tenancy — the design must not be half-applied)
- **Depends on**: none to start; blocks the "national" flip of plans/005 and any patient-dedup work
- **Category**: direction / architecture
- **Planned at**: commit `a05e716`, 2026-07-08

## Why this matters

The system is currently **hospital-partitioned**: `patients.hospital_id`,
`face_templates.hospital_id`, the `hospital.access` middleware, and the policies
all assume a patient *belongs to* one hospital. Real patient journeys don't work
that way — a citizen registers at Hospital A, is seen at B while travelling,
referred to C, treated at D. Hospital ownership produces duplicate registrations,
duplicate biometric templates, fragmented histories, and insurance-verification
pain.

The decided direction (2026-07-08) is to move to **national patient ownership**:
identity is owned nationally; hospitals own clinical *activity* (visits,
diagnoses, prescriptions, billing). The biometric layer answers **"who is this
person?"** — not "is this person registered here?" — and a **separate
access-control layer** decides what a querying hospital may see or do.

This is exactly the OpenHIE pattern used by national HIEs, including Tanzania's
own National Health Client Registry and NHIF/NIDA integration. This spike grounds
our redesign in those reference models before we touch the schema, so we migrate
once, correctly, rather than half-removing tenant isolation.

## Reference material (already gathered — read these first)

A NotebookLM research notebook was built for this:
**"National Patient Identity Architecture — Biometric Healthcare (NHIF/NIDA
scale)"** (notebook id `1fff992a-41e2-4bb2-97e4-f996a4ff5d41`, 20 sources). Query
it with `notebooklm ask "..." --notebook 1fff992a-41e2-4bb2-97e4-f996a4ff5d41`.
Key findings to build on (verify against the sources, don't take these as gospel):

- **OpenHIE separates identity from access.** The **Client Registry (CR) / Master
  Patient Index (MPI)** is the identity layer: one globally unique patient ID,
  linking facility registrations and the national ID (NIDA), probabilistic
  matching (Fellegi-Sunter) on name/DOB/biometrics. The **Interoperability Layer
  (IOL / OpenHIM)** is the access layer: single entry point / reverse proxy that
  authenticates the provider, resolves identity via the CR, then *separately*
  checks consent + authorization before releasing records.
- **Consent is a computable, granular resource** — a tuple like (Patient, Grantee
  Role, Access Scope, Status); Data Segmentation for Privacy (DS4P) tags sensitive
  sections (e.g. mental-health, reproductive, substance-use) so they can be
  filtered from cross-hospital queries.
- **Break-glass** = emergency override of consent, per-case justification, patient
  + admin notification, temporary access, fully audited.
- **Audit** = append-only, tamper-evident, who/when/which-system/what-action,
  patient self-audit, HIPAA-style retention (≥6 years).
- **FAR at national scale**: the **national ID number is a deterministic anchor**
  that shrinks the 1:N search space (biometrics are probabilistic; the NIN is not).
  Multimodal (face + fingerprint, Tanzania is adding iris) counters scale-driven
  false accepts. New enrollments run an **MPI duplicate check**; borderline matches
  go to **human adjudication**, not auto-merge.

## Current state (what the design must migrate away from)

- `laravel/app/Models/Patient.php` — `hospital_id` column; patients scoped per hospital.
- `laravel/app/Models/FaceTemplate.php` / `Fingerprint.php` — `hospital_id` on templates.
- `laravel/app/Http/Middleware/CheckHospitalAccess.php` + `laravel/app/Policies/*` —
  enforce hospital ownership on every clinical route.
- `python-service/app/services/faiss_service.py` — a single global (cross-hospital)
  face index already; hospital scoping is applied in Laravel (`FaceController::interpretCandidate`),
  which is the interim access boundary plan 005 preserves.
- Enrollment (`PatientController::enroll*`) creates a *new* patient + templates with
  no cross-hospital dedup — the fragmentation this plan must solve.

## Scope

**In scope** (this spike produces DOCS + a migration outline + a thin prototype):
- `docs/adr/013-national-patient-identity.md` (create) — the architecture decision record.
- `docs/design/national-identity-access-control.md` (create) — the detailed design.
- A schema-migration OUTLINE (not applied) describing the target tables.
- OPTIONAL thin prototype of the smallest safe slice (see Step 6), behind a flag,
  only if Steps 1–5 land and the decision points are resolved.

**Out of scope** (explicitly deferred — do NOT build in this spike):
- Removing `hospital_id` or deleting the `hospital.access` middleware.
- A full consent engine, DS4P tagging, or break-glass workflow implementation.
- Any change to the FAISS matcher's accuracy behavior.
- Real NIDA integration (design the seam; do not build the government connector).
- The "national" flip of plan 005 (that happens after this design is accepted).

## Steps

### Step 1: Map the target domain model

Document the split, grounded in the CR/MPI + IOL pattern:
- **National Patient** (identity): national patient ID, NIDA number (anchor),
  demographics, biometric templates (face + four-finger embedding), insurance
  membership.
- **Hospital-owned clinical activity**: visits, admissions, diagnoses, lab results,
  prescriptions, billing — keyed by (national_patient_id, hospital_id).
Produce an entity diagram and a table listing, for each existing table, whether it
becomes national, hospital-scoped, or a link table.

**Deliverable check**: `docs/design/...` contains the entity model + a per-table disposition.

### Step 2: Define the identity layer (our "Client Registry / MPI")

Specify how "who is this person?" resolves:
- Identity resolution returns the best *national* patient match (biometric 1:N +
  optional NIDA anchor), independent of the querying hospital.
- Deduplication on enrollment: MPI duplicate check (biometric + NIDA + demographic);
  borderline → human adjudication queue, not auto-merge.
- Define the NIDA-anchor seam: how a NIN, when present, deterministically narrows
  the search before biometric scoring.

**Deliverable check**: the design names the resolution API (inputs/outputs), the
dedup rule, and the adjudication fallback.

### Step 3: Define the access-control layer (our "IOL / consent")

Specify how "what may this hospital see/do?" is decided *after* identity resolves:
- The authorization decision point (who authenticates the provider, where consent
  is checked). **Plan 005 already introduces the seam** for the face path — a named
  `authorizeRecordAccess(patient, operatorHospitalId)` step that today returns
  `access_restricted` + audit on a cross-hospital hit. This step designs the policy
  that seam grows into (consent tuple, break-glass, referral rules) and generalizes
  it across all identification paths (face + 1:N fingerprint/hand). Do not
  re-invent the seam; enrich it.
- A minimal computable-consent model (the (Patient, Grantee Role, Access Scope,
  Status) tuple), opt-in vs opt-out choice for the pilot.
- Break-glass: the minimal emergency-override shape (justification + audit).
- What the pilot builds now vs. what is stubbed (**DECISION POINT** — see below).

**Deliverable check**: the design states the authorization flow and the pilot's
consent/break-glass scope explicitly.

### Step 4: Address FAR at national gallery scale

Document the accuracy design for a national gallery:
- Why the NIN anchor + multimodal (face + four-finger embedding) confirm is needed
  as the gallery grows (reference our existing multimodal face→fingerprint path).
- The operating-point implication: a national 1:N gallery needs a tighter
  false-accept posture than a hospital gallery; note how our thresholds (face
  IDENTIFY_THRESHOLD, contactless 57.5) and the multimodal confirm interact.

**Deliverable check**: the ADR records the FAR-scaling rationale and the
multimodal + anchor mitigation.

### Step 5: Write the ADR and the migration outline

- `docs/adr/013-national-patient-identity.md`: the decision, alternatives
  considered (hospital-owned vs national), consequences, and the sequencing (which
  plans this unblocks/blocks — e.g. it must precede the national flip of 005).
- Migration outline: the ordered, reversible steps to introduce a national patient
  ID and backfill existing hospital-scoped patients (including how duplicates
  across hospitals get merged), written so a later build-plan can execute it. Do
  NOT run any migration in this spike.

**Deliverable check**: both docs exist; the migration is described as steps, not applied.

### Step 6 (OPTIONAL): Prototype the smallest safe slice

Only if Steps 1–5 are accepted and the DECISION POINTS are resolved: prototype the
national-identity *resolution* read-path behind a feature flag — e.g. a service
that, given a biometric probe, returns a national patient id + confidence WITHOUT
changing any write path, tenancy, or the live `hospital.access` behavior. This
proves the resolution seam without migrating data.

**Deliverable check**: the prototype is flag-gated and changes no existing behavior
when the flag is off (`grep` the flag; default off).

## Decision points (STOP and get a human decision)

Pilot access posture is **DECIDED** (2026-07-08, modified option a): identity
national now; access hospital-gated + audited now (`access_restricted`, not open);
consent = phase 2. Plan 005 already implements that seam. The open decisions are:

1. **`access_restricted` client exposure** (flagged by architecture review
   2026-07-08): does the client learn that a person exists in the national system
   (status `access_restricted`, no PII), or is that suppressed to `no_match`
   externally while the identity + denial are recorded audit-only? Information-
   disclosure / existence-probe risk (journalist, political figure, celebrity).
   Currently a STOP condition in plan 005. Decide the governance posture here.
2. **Patient↔hospital ownership model** (flagged by architecture review 2026-07-08):
   is `patient->hospital_id` the right authorization basis at all, or should the
   model become **National Patient + Hospital Record** — hospitals own
   visits/diagnoses/prescriptions/labs, NOT the patient identity — so authorization
   asks "can this operator access this patient's records?" not "does this patient
   belong to my hospital?" This is the deeper model decision and drives Steps 1–2
   above. These two decisions outweigh the plan 005 code in long-term impact.
3. **Consent model**: opt-in vs opt-out for the pilot.
4. **NIDA integration depth**: design-the-seam-only vs. a mock NIDA service for the
   demo (overlaps the HOMIS mock idea; coordinate).

## Done criteria

- [ ] `docs/adr/013-national-patient-identity.md` exists with decision + consequences + sequencing.
- [ ] `docs/design/national-identity-access-control.md` exists covering identity
      layer, access layer, FAR-at-scale, and the migration outline.
- [ ] Per-table disposition (national / hospital / link) is documented.
- [ ] The three DECISION POINTS are surfaced with a recommendation each, awaiting sign-off.
- [ ] NO schema migration applied; NO tenancy/middleware removed; if Step 6 was
      done, its flag defaults off and off-state changes nothing.
- [ ] `plans/README.md` status row for 013 updated.

## STOP conditions

Stop and report back if:
- The design implies removing `hospital_id` or the `hospital.access` middleware
  before an access-control replacement exists — that is the failure mode this
  whole plan exists to prevent.
- A decision point can't be resolved from the codebase or the research notebook —
  bring it to the maintainer with options, don't guess.
- The migration outline can't be made reversible/backfillable — say so; a
  non-reversible national-ID migration is too risky to hand to a build executor.

## Maintenance notes

- This spike unblocks the "national" reshaping of plan 005 and any
  patient-deduplication work. Nothing should migrate patient ownership until this
  ADR is accepted.
- Keep the identity layer and access layer as separate modules from day one — the
  entire point is that resolving identity must never, by itself, grant data access.
- The NotebookLM notebook (`1fff992a-...`) is the living reference; re-query it as
  design questions arise rather than re-researching from scratch.
