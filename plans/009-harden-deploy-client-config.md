# Plan 009: Harden deploy & client configuration

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in "STOP
> conditions" occurs, stop and report — do not improvise. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat a05e716..HEAD -- docker-compose.yml python-service/app/main.py mobile/lib/config/app_config.dart`
> If any changed, compare the "Current state" excerpts against the live code; on a
> mismatch, treat it as a STOP condition. NOTE: `mobile/lib/config/app_config.dart`
> already shows as modified in the working tree — read its current content before
> editing.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security / dx
- **Planned at**: commit `a05e716`, 2026-07-07

## Why this matters

Four independent, low-effort configuration weaknesses, each of which makes an
insecure state the path of least resistance:

1. **Weak fallback DB passwords.** `docker-compose.yml` supplies the literal
   default `secret` for `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` when the root
   `.env` is absent, so a deploy that forgets `.env` silently comes up with a
   trivially guessable password guarding all patient PII and biometric templates —
   with no error to signal the misconfiguration.
2. **Biometric service runs in development mode in the deployed stack.** The
   deployed `python-service` container loads `python-service/.env` which sets
   `ENVIRONMENT=development`, and `main.py` only disables the interactive `/docs`
   and `/redoc` API explorers when `ENVIRONMENT == "production"`. Unlike the
   Laravel service, compose does not force production for python-service.
3. **No `python-service/.env.example`.** The service consumes `INTERNAL_API_KEY`,
   `ENVIRONMENT`, `EMBEDDING_MODEL_PATH`, etc., but ships no example file — and a
   blank `INTERNAL_API_KEY` makes the biometric endpoints unauthenticated, so a
   missing example makes the insecure default the easy path.
4. **Mobile client defaults to cleartext HTTP.** `AppConfig.baseUrl` defaults to
   `http://<LAN-IP>/api`. An APK built without the `--dart-define` override sends
   auth tokens, PII, and base64 biometric images over unencrypted HTTP.

## Current state

`docker-compose.yml` (lines 5–9):
```yaml
    environment:
      MYSQL_DATABASE: ${DB_DATABASE:-bih_db}
      MYSQL_USER: ${DB_USERNAME:-bih_user}
      MYSQL_PASSWORD: ${DB_PASSWORD:-secret}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:-secret}
```
`docker-compose.yml` (lines 20–33) — the `python-service` block has an `env_file:
./python-service/.env` but **no** `environment:` override forcing production
(contrast the `laravel` block at lines 39–45, which sets `APP_ENV: production`).

`python-service/.env` line 2: `ENVIRONMENT=development` (this file is loaded by the
deployed container). Do NOT print or copy any secret values from this file.

`python-service/app/main.py` (around lines 39, 68–69): `docs_url`/`redoc_url` are
set to `None` only when `ENVIRONMENT == "production"`.

`mobile/lib/config/app_config.dart` (lines 9–12):
```dart
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.20.10.14:8000/api',
  );
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Validate compose | `docker compose config` (if Docker available) | prints resolved config, exit 0 |
| Flutter analyze | `cd mobile && flutter analyze` | no new errors |
| Grep checks | see Done criteria | as specified |

## Scope

**In scope**:
- `docker-compose.yml` (mysql env defaults; python-service `environment:` override)
- `python-service/.env.example` (create — placeholders only, NO real secrets)
- `mobile/lib/config/app_config.dart` (default scheme → https)
- `README.md` / `python-service/README.md` — only if you must document a new required var

**Out of scope** (do NOT touch):
- Any real `.env` file (`python-service/.env`, `laravel/.env`) — never read/print/
  commit their values. You only add an `.env.example` template.
- Laravel's compose block (already forced to production).
- The `INTERNAL_API_KEY` enforcement code in `python-service/app/security.py`
  (already correct).

## Git workflow

- Branch: `advisor/009-harden-deploy-client-config`
- One commit per item. Short imperative messages.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Remove weak DB password fallbacks so a missing .env fails loudly

In `docker-compose.yml`, drop the `:-secret` defaults for the password variables so
compose errors on an unset variable instead of silently using `secret`:
```yaml
      MYSQL_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD must be set}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD must be set}
```
(The `${VAR:?message}` form makes compose fail with the message when the var is
unset — the desired fail-closed behavior.) Leave `DB_DATABASE`/`DB_USERNAME`
defaults as-is (non-sensitive).

**Verify**: `grep -n ":-secret" docker-compose.yml` → no matches.

### Step 2: Force production mode for the biometric service in the deployed stack

Add an `environment:` override to the `python-service` block mirroring the Laravel
one, so the deployed container never runs in development regardless of the `.env`:
```yaml
  python-service:
    build: ./python-service
    restart: unless-stopped
    env_file:
      - ./python-service/.env
    environment:
      ENVIRONMENT: production
    ...
```

**Verify**: read the `python-service` block and confirm `ENVIRONMENT: production`
is present under `environment:`.

### Step 3: Add python-service/.env.example

Create `python-service/.env.example` listing every consumed variable with SAFE
PLACEHOLDER values (never a real key). Include at least:
```
# Required in production — biometric endpoints are UNAUTHENTICATED if blank.
INTERNAL_API_KEY=replace-with-a-long-random-secret
# production disables the interactive API docs; development enables them.
ENVIRONMENT=production
# Optional: override the ONNX contactless embedding model path.
# EMBEDDING_MODEL_PATH=models/contactless_embedding.onnx
```
Cross-check the actual variable names by grepping the service:
`grep -rn "os.environ\|getenv" python-service/app` and include any others you find
(names only).

**Verify**: `test -f python-service/.env.example && grep -c "INTERNAL_API_KEY" python-service/.env.example` → prints `1`.

### Step 4: Default the mobile client to HTTPS

In `mobile/lib/config/app_config.dart`, change the default `baseUrl` scheme to
`https`. Because the LAN IP default is only a dev convenience, prefer a clearly
non-production placeholder host, e.g.:
```dart
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hospital.local/api',
  );
```
(Production builds already pass `--dart-define=API_BASE_URL=...`, so this only
changes the unconfigured default from cleartext to TLS.)

**Verify**: `grep -n "defaultValue: 'http://" mobile/lib/config/app_config.dart` → no matches.

## Test plan

- This is configuration; verification is the grep/existence checks in Done
  criteria plus `flutter analyze` staying clean. No new automated tests required,
  but note in the PR that any deploy must now provide the DB password vars and a
  real `INTERNAL_API_KEY`.

## Done criteria

ALL must hold:

- [ ] `grep -n ":-secret" docker-compose.yml` → no matches.
- [ ] `python-service` compose block sets `ENVIRONMENT: production` under `environment:`.
- [ ] `python-service/.env.example` exists and lists `INTERNAL_API_KEY` and `ENVIRONMENT` (placeholders only).
- [ ] `grep -n "defaultValue: 'http://" mobile/lib/config/app_config.dart` → no matches.
- [ ] `cd mobile && flutter analyze` reports no new errors.
- [ ] No real `.env` file modified or committed (`git status` shows no `python-service/.env` or `laravel/.env`).
- [ ] `plans/README.md` status row for 009 updated.

## STOP conditions

Stop and report back if:
- Grepping `python-service/app` reveals `INTERNAL_API_KEY` is NOT actually enforced
  (it is, per `security.py`, but confirm) — do not proceed to weaken anything.
- The `${VAR:?}` syntax breaks the deploy's compose version — fall back to removing
  the default entirely (`${DB_PASSWORD}`) and documenting the requirement.
- You find any real secret value while editing — do not reproduce it anywhere;
  reference `file:line` and recommend rotation, per the handling rule.

## Maintenance notes

- **Rotation**: any MySQL password that was ever brought up with the `secret`
  default must be rotated — flag this in the PR description.
- Reviewer should confirm `.env.example` contains no real credentials and that the
  mobile default is never relied on for release builds (CI/build scripts pass the
  override).
- The `INTERNAL_API_KEY`-blank-means-unauthenticated behavior is intentional for
  local dev; the `.env.example` and README note are what make the production
  requirement obvious.
