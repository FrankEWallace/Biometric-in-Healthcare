# Plan 016: Next.js admin/superadmin web dashboard

> **Executor instructions**: This is a build plan, not an audit. Work through
> the tasks in order on the single branch below — do NOT create separate
> branches per task/phase, and do NOT branch off any other in-progress plan
> branch (002, 013, etc.). This plan is additive (new directory + a small,
> named set of new Laravel endpoints); it must not require rebasing against
> the other backend plans to merge cleanly. When done, update the status row
> for 016 in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat main..HEAD -- laravel/routes/api.php laravel/app/Http/Controllers/Api`
> If new controllers/routes landed since this was planned, re-read
> `laravel/routes/api.php` before assuming the endpoint list below is complete.

## Status

- **Priority**: P2 (product surface — no current UI exists for staff/admin operations)
- **Effort**: L
- **Risk**: LOW (new, isolated directory + additive API endpoints; no changes to biometric/verification logic)
- **Depends on**: none (reads the existing API; does not require plans 003–015 to be done first)
- **Category**: feature / new surface
- **Planned at**: commit `3017b25`, 2026-07-09

## Why this matters

Right now the only web surface is the Flutter web build, which is UI-only —
staff (clerk/nurse/doctor/lab_technician/pharmacist), hospital admins, and a
national superadmin have no way to manage users, review a patient's visit
history, audit verification activity, or configure geofence/device/matcher
settings. Most of the backend API already exists (`users`, `visits`,
`visit-stages`, `audit-logs`, `hospitals`, `supervisor-overrides`) — this plan
is primarily a **consumption layer** on top of it, plus a small number of new
endpoints for the settings screens that have no backend yet.

A forked template already sits at `htdocs/nextdashboard` (MIT-licensed
`next-shadcn-admin-dashboard` / "Studio Admin", Next.js 16 + Tailwind v4 +
shadcn/Radix) with reusable pieces: app shell/sidebar, auth pages, a
tanstack-table list pattern (used for Users and Roles), a kanban board, and a
list+detail pattern with a stage/progress tracker (`logistics/shipment-details`).
This plan adapts those into this repo rather than building from scratch.

## Current state (verify before starting)

Backend endpoints that already exist and this plan will consume (confirm with
`grep -n "Route::" laravel/routes/api.php`):
- `GET/POST/PUT/DELETE /api/users` — staff management (`role:admin,super_admin`)
- `GET /api/visits`, `GET /api/visits/{visit}`, `GET /api/visits/patient-search`, `GET /api/queue`
- `POST /api/visits/{visit}/stages/{stage}/verify`, `PUT .../stages/{stage}/data`
- `GET /api/verify/logs`, `GET /api/verify/logs/{log}`
- `GET /api/audit-logs`
- `GET/POST/PUT/DELETE /api/hospitals` (`role:super_admin` for create/delete)
- `GET/POST/PUT /api/supervisor-overrides`
- `POST /api/auth/login`, `GET /api/auth/me`, `POST /api/auth/logout` (Sanctum)

Confirmed **absent** (grepped `laravel/routes/api.php`, no hits for
geofence/device/threshold/matcher/config) — these need new, small backend
endpoints as part of this plan:
- Geofence boundary CRUD per hospital (WiFi SSID allowlist + GPS polygon)
- Device/pairing list (which devices have verified from where, last seen)
- Matcher threshold config (currently, if configurable at all, it's an env var —
  confirm in `python-service/app/config.py` / `.env` before assuming a DB-backed
  settings table doesn't exist)

Template reference (already forked, MIT license, do not vendor a fresh copy —
`htdocs/nextdashboard/nextdashboard`):
- `src/app/(main)/dashboard/_components/sidebar/*` — shell/nav/account-switcher
- `src/app/(main)/auth/v2/login` — login page
- `src/app/(main)/dashboard/users/_components/*` — table+toolbar pattern
- `src/app/(main)/dashboard/roles/_components/*` — same pattern, filter variant
- `src/app/(main)/dashboard/default/_components/*` — metric cards + table
- `src/app/(main)/dashboard/kanban/_components/*` — board pattern
- `src/app/(main)/dashboard/logistics/_components/shipment-details.tsx` — list+detail
  with a stage progress ring/badges + tabs (closest fit for the visit timeline)
- `src/components/ui/*` — shadcn primitives (table, card, tabs, badge, dialog, etc.)

## Scope

**In scope**:
- New top-level directory `web-admin/` in this repo (copied/adapted from the
  forked template — a plain copy-in, not a git submodule; simplest for this
  project's size and avoids submodule-sync overhead for a solo/FYP scope).
- Auth against the existing Sanctum API (token-based, since this is a separate
  origin from the Laravel app — not cookie/SPA auth).
- Screens: login, role-gated shell/nav, overview dashboard, staff management,
  roles/permissions (superadmin), patient management + visit timeline,
  visit-ops kanban, audit log, device & geofence settings, facility management
  (superadmin), matcher threshold config (superadmin).
- New Laravel endpoints strictly for: geofence CRUD, device/pairing list,
  matcher threshold config — additive only, under a `role:super_admin` (or
  `admin` where hospital-scoped) gate, following the existing controller/route
  conventions.

**Out of scope** (do NOT touch):
- Any change to biometric matching, verification logic, or the Flutter app.
- Any of the other plans' branches (002–015) — do not rebase onto them or pull
  their in-progress changes in.
- Real-time features (websockets/chat/mail) from the template — not needed.
- CRM/Finance/Ecommerce/Logistics/Invoice/Academy template dashboards — not
  adapted, not deleted from the template fork, simply unused.

## Git workflow

- **One branch for the whole feature**: `feature/016-nextjs-admin-dashboard`,
  branched from `main` (not from `advisor/002-stage-embedding-core` or any
  other in-progress plan branch).
- Commit per task below (see Tasks). Do not split this work across multiple
  branches or PRs unless asked.
- Do not push or open a PR unless instructed.

## Tasks

### Task 1 — Scaffold `web-admin/` and wire API auth
Copy the template's app shell into `web-admin/` (package.json, `src/app/(main)`
layout, `src/components/ui`, `src/lib`, `src/navigation`). Strip CRM/Finance/
Ecommerce/Logistics/Invoice/Academy/Mail/Chat routes and their nav entries —
keep only what later tasks need. Add an API client (fetch wrapper) pointed at
the Laravel API base URL (env var), with a token-based Sanctum auth flow
(login → store token → attach `Authorization: Bearer` header), since this is a
separate origin from Laravel, not same-origin SPA cookie auth.
**Verify**: `cd web-admin && npm run build` succeeds; login page renders; a
successful login against a real `POST /api/auth/login` stores a token and
redirects to the dashboard shell.

### Task 2 — Role-gated shell and nav
Adapt `dashboard/_components/sidebar/*` so nav items are filtered by the
logged-in user's role (`admin` vs `super_admin`; clerk/nurse/doctor/lab_tech/
pharmacist get no dashboard access — this is a staff/admin tool, not a
clinical capture UI). Superadmin-only items: Facility management, Roles,
Matcher config. Admin items: Staff, Patients, Visit ops, Audit log, Geofence &
Devices.
**Verify**: log in as an `admin` user (via API) and confirm superadmin-only nav
items are absent; log in as `super_admin` and confirm all items are present.

### Task 3 — Overview dashboard
Adapt `dashboard/default/_components/*` (metric cards + table) into an
overview screen: verification volume, enrollment count, failed-match rate,
recent visits table (replacing "recent customers"). Admin sees their hospital
only; superadmin sees an aggregate + a hospital selector, sourced from
`GET /api/hospitals` + `GET /api/visits`.
**Verify**: cards render real counts from the API (not the template's mock
`data.json`); hospital selector changes the scope for superadmin only.

### Task 4 — Staff management
Adapt `dashboard/users/_components/*` (table + toolbar + columns) against
`GET/POST/PUT/DELETE /api/users`. Columns: name, role, hospital, status, last
active. Create/edit as a dialog form (shadcn `dialog` + `field`), not a full
page nav.
**Verify**: create, edit, and deactivate a staff account through the UI and
confirm each action round-trips to the real API (check via `GET /api/users`).

### Task 5 — Roles/permissions (superadmin)
Adapt `dashboard/roles/_components/*` against whatever role model the backend
actually exposes today (check `laravel/app/Models/User.php` / any `Role`
model/enum before assuming a dedicated roles table exists — if roles are a
fixed enum rather than a manageable table, this screen is read-only/reference,
not full CRUD; do not invent backend role-CRUD endpoints that don't exist
without flagging it first).
**Verify**: screen reflects the real, current set of roles in the system,
whatever their backend representation turns out to be.

### Task 6 — Patient management + visit timeline
Build a list+detail split view: patient list/search on the left (against
`GET /api/patients`, `GET /api/visits/patient-search`), and on the right a
per-visit detail panel modeled on `logistics/shipment-details.tsx` — a stage
progress indicator across `clerk_checkin → triage → consultation →
laboratory → pharmacy → clerk_checkout` (colored by status: pending/
completed/override), with tabs for each stage's data (vitals, diagnosis/labs,
pharmacy) sourced from `GET /api/visits/{visit}` and its stage data. Show who
verified each stage and when, and flag any `SupervisorOverride`.
**Verify**: selecting a patient with a real in-progress visit shows accurate
per-stage status and data pulled from the API, not placeholder content.

### Task 7 — Visit-ops kanban
Adapt `dashboard/kanban/_components/*` into a board of in-progress visits,
columns = the six stages, cards = patient + time-in-stage, sourced from
`GET /api/queue`. This is the ops-level view; Task 6 is the per-patient
drill-down — keep them as separate screens, don't merge.
**Verify**: a visit's card appears in the column matching its current stage
and moves when the stage is verified (poll or refetch, no drag-to-advance).

### Task 8 — Audit log
Adapt the users/roles table pattern (filters + search, no custom layout
needed) against `GET /api/audit-logs`: timestamp, actor, action, target,
result columns, filterable by date range/actor/action.
**Verify**: filtering by actor and date range narrows results correctly
against real audit-log rows.

### Task 9 — Device & geofence settings (new backend + frontend)
Add the missing backend pieces first: a `geofence_boundaries` (or similar)
table + controller for per-hospital GPS polygon + WiFi SSID allowlist CRUD,
and a read endpoint listing devices/last-seen (derive from existing
verification logs if no device-pairing table exists yet — check before adding
a new table you don't need). Gate writes to `role:admin,super_admin`,
hospital-scoped for `admin`. Frontend: SSID allowlist as a simple list/table;
GPS boundary as a map editor (`d3-geo` + adapt `logistics/shipment-route-map.tsx`
for drawing/editing a polygon instead of a route).
**Verify**: an admin can view and edit their hospital's SSID list and GPS
boundary through the UI, and the existing `EnforceGeofence` middleware behavior
is unchanged (do not touch `GeofenceService`/`EnforceGeofence.php` logic itself
— this task only adds an admin-facing CRUD surface over hospital-scoped config
that likely already backs that middleware; confirm the current source of
geofence config before adding a parallel one).

### Task 10 — Facility management (superadmin)
Adapt the users/roles table pattern against `GET/POST/PUT/DELETE /api/hospitals`
(`role:super_admin` for create/delete, `super_admin,admin` for update, per the
existing route gates). Columns: name, region, admin, active staff count,
status.
**Verify**: superadmin can onboard a new facility and assign its admin through
the UI, using only the existing hospital endpoints.

### Task 11 — Matcher threshold config (superadmin)
Confirm first whether thresholds are env-var-only today (`python-service`
config) or already backed by a settings table/endpoint. If env-var-only, this
task is a **read-only display** of current thresholds (not a live-editable
control) unless a backend settings endpoint is added — do not wire a UI
control to something that silently no-ops. Flag this as a decision point if
the backend doesn't support it; do not build a fake control.
**Verify**: whatever is shown reflects the actual value the matcher is using
at runtime, not a hardcoded template default.

## Test plan

- No existing Laravel/Python test suites should regress — new endpoints (Task
  9) get their own feature tests following the existing `tests/Feature/*`
  pattern (see `VisitStageVerifyTest.php` for style); run
  `cd laravel && composer test` after Task 9.
- Frontend: no test infra exists yet in the template beyond build/typecheck —
  at minimum, `npm run build` and `npm run check` (biome) must pass after every
  task; do not introduce a new frontend test framework as part of this plan.
- Manual verification per task as specified above, against the real API (a
  local Laravel dev server), not the template's mock JSON data.

## Done criteria

ALL must hold:

- [ ] `web-admin/` builds (`npm run build`) and lints (`npm run check`) clean.
- [ ] Login, role-gated nav, overview, staff management, patient management +
      visit timeline, visit-ops kanban, audit log, device & geofence settings,
      facility management, and matcher-config screens all exist and read/write
      through the real Laravel API — no screen is left wired to template mock
      data.
- [ ] New backend endpoints (Task 9, and Task 11 if applicable) have feature
      tests; `composer test` passes.
- [ ] No file outside `web-admin/` and the specific new endpoints/tests changed
      — no edits to biometric/verification/Flutter code.
- [ ] `plans/README.md` status row for 016 updated.

## STOP conditions

Stop and report back if:
- The role model turns out to be more/less granular than the fixed
  clerk/nurse/doctor/lab_technician/pharmacist/admin/super_admin set assumed
  here (Task 5) — don't invent role-CRUD the backend doesn't support.
- Matcher thresholds are hardcoded in a way that isn't safely exposable as
  config at all (e.g. baked into a compiled model artifact) — report instead
  of building a control that can't actually change anything.
- Geofence config already exists somewhere non-obvious (e.g. inline on the
  `Hospital` model) — reuse it, don't create a parallel/duplicate source of
  truth; report if this changes Task 9's scope materially.

## Maintenance notes

- Keep `web-admin/` decoupled from `htdocs/nextdashboard` after the initial
  copy-in — it's a one-time adaptation, not a synced fork; don't set up
  tooling to pull template updates automatically.
- Future clinical-data screens (real vitals/prescription entry, not
  simulated) are out of scope here and depend on the product decision noted
  earlier: whether stage payloads stay simulated for the FYP or become a real
  EMR feature.
