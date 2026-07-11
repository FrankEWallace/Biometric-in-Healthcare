# Plan 020: Harden web-admin auth (token storage, TLS cookies, server role gate) and add its CI + typecheck gate

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`. This plan has TWO largely independent halves (A: auth
> hardening, B: CI + typecheck). B is small and safe; if A hits a STOP
> condition you may still land B.
>
> **Drift check (run first)**: `git diff --stat d25ce31..HEAD -- web-admin/ .github/workflows/ci.yml`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L (A is L; B is S)
- **Risk**: MED
- **Depends on**: none
- **Category**: security + dx
- **Planned at**: commit `d25ce31`, 2026-07-11

## Why this matters

`web-admin/` (the Next.js admin/superadmin dashboard, added by plan 016) holds
a Sanctum API token for a system full of patient PII and biometric audit data.
Today that token lives in a **JS-readable cookie** written via `document.cookie`
with **no `Secure`/`SameSite`**, read back on every request to build the
`Authorization` header. Any XSS or malicious dependency exfiltrates a full
admin token. The dashboard's admin/super_admin gate is **client-trusted**: the
role comes from a user-forgeable cookie and the server layout trusts it.
Server-side per-endpoint ACLs in Laravel bound the blast radius (forged roles
get 403s), so this is a defence-in-depth / confused-deputy gap — real, not
catastrophic. Separately, web-admin is the **only one of four services with no
CI gate** and has no `tsc` typecheck script, so type/build regressions land
on `main` undetected.

## Current state

- `web-admin/src/lib/cookie.client.ts:10-13` — `setClientCookie` writes
  `${key}=${value}; expires=...; path=/` — no `Secure`, no `SameSite`, not
  `HttpOnly` (impossible from JS).
- `web-admin/src/lib/auth/cookies.ts` — names: `bih_admin_token`,
  `bih_admin_user`.
- `web-admin/src/lib/api.ts:5,18-30` — `API_BASE_URL` from
  `NEXT_PUBLIC_API_URL`; `request()` reads the token via
  `getClientCookie(AUTH_TOKEN_COOKIE)` and sets `Authorization: Bearer`.
  **No 401 handling** (that gap is plan 021's concern; do not duplicate here).
- `web-admin/src/lib/auth/auth-context.tsx:38-41,58-72` — writes token + user
  JSON into client cookies; `DASHBOARD_ROLES` check runs client-side after a
  shared `/auth/login` (comment at `:13-15`: "rejects them here, not on the API").
- `web-admin/src/lib/auth/session.server.ts:10-25` — `getServerSession` parses
  the role from the client-written `bih_admin_user` cookie (forgeable).
- `web-admin/src/app/(dashboard)/layout.tsx` — server layout redirects only on
  `!session`; never checks role.
- Laravel enforces roles per-endpoint (e.g. `laravel/routes/api.php` — admin/
  super_admin middleware on facilities, matcher-config, users) and exposes
  `GET /auth/me` (`routes/api.php:50`, authenticated, all roles) returning the
  authenticated user — usable for server-side role re-verification.
- `.github/workflows/ci.yml` — jobs `python`, `laravel`, `flutter` only; no
  `web-admin` job. `web-admin/package.json` scripts: `dev/build/start`,
  `lint/format/check` (Biome), **no `typecheck`**.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd web-admin && npm ci` | exit 0 |
| Biome | `cd web-admin && npm run check` | exit 0 |
| Build | `cd web-admin && npm run build` | exit 0 |
| Typecheck (after step B1) | `cd web-admin && npm run typecheck` | exit 0, no errors |

## Scope

**In scope**:
- Part A: `web-admin/src/lib/cookie.client.ts`,
  `web-admin/src/lib/auth/auth-context.tsx`,
  `web-admin/src/lib/auth/session.server.ts`,
  `web-admin/src/app/(dashboard)/layout.tsx`
- Part B: `web-admin/package.json`, `.github/workflows/ci.yml`
- `plans/README.md` (status row)

**Out of scope**:
- A full BFF/token-proxy rewrite (route handlers that hold an HttpOnly cookie
  and proxy `/api/*`). That is the ideal end state but is a larger design
  change — this plan does the high-value subset that needs no architecture
  shift. If you believe only a BFF truly fixes SEC-01, STOP and report; do not
  half-build a proxy.
- 401-handling / data-layer error states — plan 021.
- Laravel code — `GET /auth/me` and the ACLs already exist; do not modify them.
- Any `src/app/(dashboard)/*/page.tsx` data screens.

## Git workflow

- Branch: `advisor/020-web-admin-auth-and-ci`
- Commit style: imperative subject + `(plan 020)` suffix; separate commits for
  Part A and Part B.
- Do NOT push or open a PR unless the operator instructed it.

## Steps — Part B first (small, safe, unblocks CI)

### Step B1: Add a typecheck script

In `web-admin/package.json` scripts add `"typecheck": "tsc --noEmit"`.
Confirm `typescript` is already a devDependency (it is, for a Next+TS app); if
not, STOP and report rather than adding it blind.

**Verify**: `cd web-admin && npm run typecheck` → exit 0 (fix any surfaced type
errors only if trivial and in-scope files; otherwise report them).

### Step B2: Add a web-admin CI job

In `.github/workflows/ci.yml` add a fourth job mirroring the `flutter` job's
structure (checkout → setup-node → install → checks), using
`actions/setup-node` with the repo's Node version (check `web-admin/.nvmrc` or
`package.json` `engines`; default to Node 20 if unspecified) and
`working-directory: web-admin`:

```yaml
  web-admin:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install dependencies
        working-directory: web-admin
        run: npm ci
      - name: Check
        working-directory: web-admin
        run: npm run check
      - name: Typecheck
        working-directory: web-admin
        run: npm run typecheck
      - name: Build
        working-directory: web-admin
        run: npm run build
```

Match the exact `uses:` action versions already used by the other jobs in this
file (read them; do not assume `@v4`).

**Verify**: the YAML is valid — `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0. (Real CI runs on push.)

## Steps — Part A

### Step A1: Harden the cookie writer

In `cookie.client.ts`, append `Secure` and `SameSite=Strict` to the cookie
string. Because `Secure` cookies are dropped over plaintext HTTP (the dev LAN
setup), gate it on the page protocol:

```ts
const secure = typeof location !== "undefined" && location.protocol === "https:" ? "; Secure" : "";
writeClientCookie(`${key}=${value}; expires=${expires}; path=/; SameSite=Strict${secure}`);
```

**Verify**: `cd web-admin && npm run typecheck && npm run build` → exit 0.

### Step A2: Re-verify role server-side in the dashboard layout

Change `session.server.ts` `getServerSession` (or add a helper it calls) to
stop trusting the role from the `bih_admin_user` cookie for gating. In the
server layout `(dashboard)/layout.tsx`, after confirming a token exists, call
`GET /auth/me` server-side with that token and redirect to `/login` unless the
returned role is in `{admin, super_admin}`. Keep the existing `!session`
redirect. Do NOT remove the client-side `DASHBOARD_ROLES` check in
`auth-context.tsx` (it gives immediate login feedback) — the server check is
the authoritative addition.

Target shape (in the layout, server component):
```ts
const session = await getServerSession();
if (!session) redirect("/login");
const me = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/auth/me`, {
  headers: { Authorization: `Bearer ${session.token}`, Accept: "application/json" },
  cache: "no-store",
});
if (!me.ok) redirect("/login");
const { role } = (await me.json()).user ?? {};
if (role !== "admin" && role !== "super_admin") redirect("/login");
```
(Confirm the `/auth/me` response shape first — read `AuthController::me` in
`laravel/app/Http/Controllers/Api/AuthController.php`; adapt the destructuring
to the actual keys.)

**Verify**: `cd web-admin && npm run typecheck && npm run build` → exit 0.

### Step A3: Document the HTTP-is-dev-only constraint

Add a comment in `cookie.client.ts` noting that `Secure` requires the
dashboard and API to be served over TLS in any non-dev deployment, and that
the LAN/HTTP setup (`NEXT_PUBLIC_API_URL=http://…`) is development-only.

**Verify**: n/a (comment).

## Test plan

web-admin has no test runner yet; this plan does not add one (a future plan
can). Verification is `npm run check` + `npm run typecheck` + `npm run build`
all green, plus the new CI job enforcing them. Manually confirm (report the
result): logging in as an `admin` reaches `/dashboard`; a forged
`bih_admin_user` cookie with `role: super_admin` no longer loads a
super_admin-only route (server `/auth/me` returns the real role).

## Done criteria

- [ ] `grep -n "SameSite" web-admin/src/lib/cookie.client.ts` → present
- [ ] `(dashboard)/layout.tsx` calls `/auth/me` and gates on role server-side
- [ ] `web-admin/package.json` has a `typecheck` script; `npm run typecheck` exits 0
- [ ] `.github/workflows/ci.yml` has a `web-admin` job running check + typecheck + build
- [ ] `cd web-admin && npm run build` exits 0
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- You conclude the token exposure can only be closed by a full BFF/proxy — land
  Parts A2/A3/B, report SEC-01 as needing a follow-up BFF plan.
- `GET /auth/me`'s response shape doesn't include the role — report; the
  server gate can't be completed without it.
- `npm run typecheck` surfaces many pre-existing type errors — land Part B's
  CI wiring but report the errors as a separate finding rather than fixing an
  open-ended list.
- `npm ci` fails (lockfile drift) — report; do not regenerate the lockfile.

## Maintenance notes

- The real fix for SEC-01 (token never in JS) is a BFF that proxies `/api/*`
  behind an HttpOnly cookie — deferred here; if the dashboard ever renders
  untrusted content, escalate it.
- Reviewer: confirm `Secure` is conditional on HTTPS (so dev LAN still works)
  and the server role gate uses `no-store` (no stale role caching).
- Once the `web-admin` CI job is green, treat a red one as merge-blocking like
  the other three services.
