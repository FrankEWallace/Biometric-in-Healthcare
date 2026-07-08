# Plan 003: Stop trusting arbitrary proxies so the hospital IP gate and audit log can't be spoofed

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise. When
> done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- laravel/bootstrap/app.php laravel/app/Http/Middleware/CheckHospitalAccess.php`
> If any in-scope file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

`laravel/bootstrap/app.php` calls `$middleware->trustProxies(at: '*')`, which
tells Laravel to trust the entire `X-Forwarded-For` chain from any upstream. As a
result `$request->ip()` is derived from a client-supplied header. Two controls
depend on that value:

1. `CheckHospitalAccess` — the "hospital network only" gate fronting every
   clinical route group (`patients`, `fingerprint`, `verify`, `face`, `visits`,
   `supervisor-overrides`) — authorizes on `$request->ip()` against private CIDRs.
2. `AuditLog::record()` writes `ip_address => $request->ip()` into the tamper-
   evidence trail.

With all proxies trusted, a request carrying a forged private-range
`X-Forwarded-For` from the public internet can satisfy the network gate and write
a falsified source IP into the patient/biometric audit log. The fix is to trust
only the real reverse proxy (Nginx Proxy Manager) that fronts the stack, so the
forwarded chain can no longer be attacker-controlled.

## Current state

`laravel/bootstrap/app.php` (around lines 22–27):
```php
->withMiddleware(function (Middleware $middleware): void {
    // Trust the immediate upstream proxy (NPM) so X-Forwarded-Proto is
    // honored — the Laravel container is only reachable via the internal
    // Docker network from NPM, never directly from the internet.
    $middleware->trustProxies(at: '*');
    ...
```
The comment already states the intent (trust only NPM) but the code trusts `'*'`.

`docker-compose.yml` shows the topology: the `laravel` service is on both
`proxy-net` (external, shared with NPM) and `internal`; it is `expose: 80` only,
never `ports:`-published. So in production Laravel is reached exclusively through
NPM over `proxy-net`.

`laravel/app/Http/Middleware/CheckHospitalAccess.php` (around lines 32, 45–59)
reads `$request->ip()` and compares against private CIDR defaults — this is the
gate that becomes spoofable.

Laravel's `trustProxies` accepts a specific IP/CIDR string or array instead of
`'*'`. Because the NPM container's address on `proxy-net` is assigned by Docker
and can change, the robust choice is to trust the Docker bridge subnet that
`proxy-net` uses (a private range), OR to pin NPM's address. See STOP conditions
for how to determine the right value rather than guessing.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Laravel tests | `cd laravel && composer test` | all pass |
| Inspect proxy net (if Docker available) | `docker network inspect proxy-net` | shows subnet + NPM container IP |
| Grep for trustProxies | `grep -rn "trustProxies" laravel/bootstrap/app.php` | one call, no `'*'` after fix |

## Scope

**In scope**:
- `laravel/bootstrap/app.php` (the `trustProxies` call)
- `laravel/tests/Feature/` — add `ForwardedIpTrustTest.php` (create)

**Out of scope** (do NOT touch):
- `CheckHospitalAccess.php` logic — it stays as defense-in-depth; do not weaken or
  remove it. This plan only fixes what feeds it.
- CORS / other middleware in the same closure.
- `docker-compose.yml` — no topology change needed here (SEC hardening of compose
  is plan 009).

## Git workflow

- Branch: `advisor/003-fix-proxy-trust-ip-gate`
- One commit for the config change, one for the test.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Trust only the reverse proxy subnet, sourced from config

Replace `trustProxies(at: '*')` with a value read from env so ops can pin it
without a code change, defaulting to the private Docker bridge range that
`proxy-net` uses:
```php
// Trust only the reverse proxy (Nginx Proxy Manager) that fronts this stack.
// Laravel is reachable ONLY via NPM over the internal Docker network, so the
// forwarded chain must come from that proxy — never trust '*', which lets a
// client forge X-Forwarded-For to spoof the hospital IP gate and audit log.
$middleware->trustProxies(
    at: explode(',', (string) env('TRUSTED_PROXIES', '172.16.0.0/12')),
);
```
Add `TRUSTED_PROXIES` to `laravel/.env.example` with a comment explaining it must
be set to NPM's address/subnet in production. (Editing `.env.example` is permitted
here as a doc file; do not touch a real `.env`.)

**Verify**: `grep -n "trustProxies(at: '\*')" laravel/bootstrap/app.php` → no matches.

### Step 2: Add a regression test that a forged forwarded IP is not trusted

Create `laravel/tests/Feature/ForwardedIpTrustTest.php`. With `TRUSTED_PROXIES`
set to a subnet that does NOT include the test client, assert that a request
sending `X-Forwarded-For: <a private hospital-range IP>` does **not** cause
`$request->ip()` to return that forged value — i.e. the hospital-access gate on a
protected route still denies. Model the request/auth setup on an existing feature
test that hits a `hospital.access` route (e.g. `PatientTest.php`).

Assert at the behavior level: an authenticated user coming from a non-hospital
address who spoofs `X-Forwarded-For` receives the hospital-access denial, proving
the header is no longer honored.

**Verify**: `cd laravel && php artisan test --filter ForwardedIpTrust` → passes.

## Test plan

- New file `laravel/tests/Feature/ForwardedIpTrustTest.php`: one test that a
  spoofed `X-Forwarded-For` does not satisfy the IP gate; one that a request
  genuinely from the trusted proxy subnet with a legitimate forwarded hospital IP
  still works (so the fix doesn't break real traffic).
- Pattern: `PatientTest.php` for auth + protected-route setup.
- Verification: `cd laravel && composer test` → green including the new file.

## Done criteria

ALL must hold:

- [ ] `grep -n "'\*'" laravel/bootstrap/app.php` returns nothing on the trustProxies line.
- [ ] `TRUSTED_PROXIES` documented in `laravel/.env.example`.
- [ ] `cd laravel && composer test` exits 0; `ForwardedIpTrustTest` passes.
- [ ] No files outside the in-scope list + `.env.example` modified (`git status`).
- [ ] `plans/README.md` status row for 003 updated.

## STOP conditions

Stop and report back if:
- You cannot determine the correct trusted subnet/IP for NPM (no Docker access to
  run `docker network inspect proxy-net`). Report the default you used
  (`172.16.0.0/12` covers common Docker bridge ranges) and flag that ops must
  confirm and pin `TRUSTED_PROXIES` before production, rather than guessing a
  narrower value that could 403 all traffic.
- Setting a restrictive `TRUSTED_PROXIES` makes the existing test suite fail
  because tests rely on `X-Forwarded-For` — that means other code trusts the
  header too; report it.
- `CheckHospitalAccess` turns out to read a header directly rather than
  `$request->ip()` — then the fix location differs; report before changing.

## Maintenance notes

- If the deployment moves off NPM or adds another proxy hop, `TRUSTED_PROXIES`
  must be updated to match, or the gate breaks (fail-closed on legit traffic).
- Reviewer should confirm the audit log now records the real client IP for
  internal traffic and cannot be set from a forged header.
- Related hardening (compose default passwords, python-service prod env) is plan 009.
