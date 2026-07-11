# Plan 021: Fix web-admin data-layer correctness — 401 handling, load races, pagination, render guard

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat d25ce31..HEAD -- web-admin/src/lib/api.ts web-admin/src/app/\(dashboard\)`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Depends on**: 020 (do 020 first — it establishes the web-admin CI/typecheck
  gate this plan relies on for verification; not a hard code dependency)
- **Category**: bug
- **Planned at**: commit `d25ce31`, 2026-07-11

## Why this matters

Every web-admin data screen loads with a `.then(...).finally(...)` chain and
**no `.catch`**, and `api.ts` has **no 401 handling**. So an expired/revoked
Sanctum token, a 500, or a network drop rejects an unhandled promise, flips
`isLoading` off, and renders an empty table reading "No entries" —
indistinguishable from genuinely-empty data, and actively misleading on the
audit log. An expired session never routes to `/login`; the admin just sees
blank screens. Two loaders also have stale-data races (selecting patient B
before A resolves can show A's clinical timeline under B), the patients screen
only ever shows API page 1, and the audit-log action formatter throws on an
empty segment (blanking the whole table, with no error boundary). For a system
whose job is accurate patient identification, showing the wrong or stale data
silently is the worst failure mode.

## Current state

- `web-admin/src/lib/api.ts:18-40` — `request()`; on `!res.ok` it throws
  `ApiError`, but nothing maps 401 → logout/redirect. Token read at `:19`.
- The GOOD pattern to copy — `web-admin/src/app/(dashboard)/dashboard/page.tsx:40-68`
  uses a `let cancelled = false` flag, checks `if (cancelled) return` before
  every `setState`, and returns a cleanup that sets `cancelled = true`. It is
  also the only loader with a `.catch` (`:56`). Use it as the template.
- Loaders MISSING `.catch` / cancellation (all under
  `web-admin/src/app/(dashboard)/`): `audit-log/page.tsx:33-47`,
  `staff/page.tsx:29-31`, `facilities/page.tsx:22-28`,
  `matcher-config/page.tsx:27-29`, `patients/page.tsx:31-33` and `:42-51`,
  `geofence-devices/page.tsx:25-28,37-39`, `visit-ops/page.tsx:20-22`.
- Race — `patients/page.tsx:38-51` `selectPatient`: nested `.then` chains, no
  cancellation, no `.catch` (a rejected `findVisitForPatient` strands
  `visitState` on `"loading"` forever). `audit-log/page.tsx` filter/page
  changes fire overlapping requests with no ordering guard.
- Pagination discarded — `web-admin/src/lib/patients/api.ts:68-72`:
  ```ts
  const page = await api.get<Paginated<PatientListItem>>(`/patients${query}`);
  return page.data; // total / last_page thrown away
  ```
  The audit-log page (`audit-log/page.tsx:64-75`) already implements working
  pagination — copy its shape.
- Render guard — `audit-log/_components/audit-log-table.tsx:10-15`:
  `action.split("_").map((w) => w[0].toUpperCase() + w.slice(1))` throws
  `TypeError` if any segment is empty (leading/trailing/double underscore);
  `entry.action` is typed as raw `string`. No error boundary in the tree.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd web-admin && npm ci` | exit 0 |
| Typecheck | `cd web-admin && npm run typecheck` | exit 0 (script added in plan 020) |
| Check | `cd web-admin && npm run check` | exit 0 |
| Build | `cd web-admin && npm run build` | exit 0 |

## Scope

**In scope**:
- `web-admin/src/lib/api.ts` (401 handling)
- The eight `(dashboard)/*/page.tsx` loaders listed above
- `web-admin/src/lib/patients/api.ts` + `patients/page.tsx` +
  `patients/_components/*` (pagination UI)
- `web-admin/src/app/(dashboard)/audit-log/_components/audit-log-table.tsx`
  (render guard)
- A small shared error-UI component under `web-admin/src/components/`
- `plans/README.md` (status row)

**Out of scope**:
- Auth token storage / cookie flags / server role gate — plan 020.
- Any Laravel code (the APIs already paginate).
- Restyling the tables beyond adding an error state + pagination controls.

## Git workflow

- Branch: `advisor/021-web-admin-data-layer-correctness`
- Commit style: imperative subject + `(plan 021)` suffix; a commit per
  numbered step is reasonable.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Central 401 handling in api.ts

In `request()`, when `res.status === 401`, clear the session cookies
(`deleteClientCookie` for both `AUTH_TOKEN_COOKIE` and `AUTH_USER_COOKIE`) and
redirect to `/login` (`window.location.href = "/login"` is acceptable here
since this is the client fetch layer), then still throw so callers stop. Guard
for SSR (`typeof window !== "undefined"`).

**Verify**: `cd web-admin && npm run typecheck` → exit 0.

### Step 2: Add a reusable load-error state

Create `web-admin/src/components/load-error.tsx` — a small component
(`{ message?: string; onRetry?: () => void }`) matching the repo's shadcn/Tailwind
style (look at an existing `src/components/ui/*` for tokens). It renders a
distinct "Couldn't load — Retry" panel, visually different from the empty
state.

**Verify**: `npm run typecheck` → exit 0.

### Step 3: Give every loader a catch + error state + cancellation

For each of the eight loaders, refactor to the `dashboard/page.tsx` pattern:
`let cancelled = false`, `if (cancelled) return` before each setState, cleanup
sets `cancelled = true`, and a `.catch` that (a) ignores if cancelled, (b) sets
a local `error` state rendered via `<LoadError onRetry={...} />`. Distinguish
"loading" / "error" / "empty" / "loaded".

**Verify**: `npm run typecheck && npm run check` → exit 0.

### Step 4: Fix the patients selectPatient race + stuck-loading

In `patients/page.tsx` `selectPatient`, add a per-selection guard (a
`selectionId`/ref incremented each call; ignore resolutions whose id is stale)
so selecting B before A resolves never renders A under B. Add `.catch` that
resets `visitState` to an error/`"none"` state instead of leaving `"loading"`.

**Verify**: `npm run typecheck` → exit 0; manually (report): rapidly clicking
two patients shows the second patient's data, never the first's.

### Step 5: Thread patients pagination

Change `getPatients` (`patients/api.ts:68-72`) to return the full
`Paginated<PatientListItem>` (or `{ data, total, lastPage, page }`), accepting
a `page` arg. Add prev/next controls to the patients screen mirroring
`audit-log/page.tsx:64-75`. Reset to page 1 when `search` changes.

**Verify**: `npm run typecheck && npm run build` → exit 0.

### Step 6: Guard actionLabel

In `audit-log-table.tsx`, make `actionLabel` empty-segment safe:
`.split("_").filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ")`.

**Verify**: `npm run build` → exit 0.

## Test plan

No test runner in web-admin (a future plan may add one). Verification is
`npm run typecheck` + `npm run check` + `npm run build` green, plus these
manual checks (report results):
- Load any screen with the API stopped → shows the LoadError panel with Retry,
  not an empty table.
- Expire/clear the token, trigger a fetch → redirected to `/login`.
- Rapidly select two patients → second wins.
- Patients list with >1 page → page 2 reachable via controls.

## Done criteria

- [ ] `grep -n "401" web-admin/src/lib/api.ts` → 401 branch present
- [ ] `grep -rLn "\.catch(" web-admin/src/app/(dashboard)/audit-log/page.tsx web-admin/src/app/(dashboard)/staff/page.tsx web-admin/src/app/(dashboard)/facilities/page.tsx web-admin/src/app/(dashboard)/patients/page.tsx web-admin/src/app/(dashboard)/geofence-devices/page.tsx web-admin/src/app/(dashboard)/visit-ops/page.tsx web-admin/src/app/(dashboard)/matcher-config/page.tsx` → no files listed (all now have `.catch`)
- [ ] `web-admin/src/lib/patients/api.ts` returns pagination metadata; patients screen has prev/next
- [ ] `actionLabel` filters empty segments
- [ ] `cd web-admin && npm run typecheck && npm run check && npm run build` all exit 0
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `GET /patients` does not actually return a paginated envelope
  (`data`/`total`/`last_page`) — inspect the response; if it returns a bare
  array, pagination (step 5) is a server change and out of scope.
- The loader files have drifted materially from the excerpts.
- Adding the 401 redirect causes a redirect loop with the login page (the
  login screen itself must not run an authenticated loader) — report the loop.

## Maintenance notes

- New data screens must adopt the `dashboard/page.tsx` cancellation+catch
  pattern; consider extracting a `useLoad` hook in a follow-up so it's not
  re-implemented each time.
- Reviewer: confirm the 401 handler can't loop on `/login` and that empty vs
  error states are visually distinct.
- Deferred: unbounded list fetches on staff/devices/facilities
  (PERF-01) — real at national scale, left for a pagination-focused pass;
  noted in plans/README "considered".
