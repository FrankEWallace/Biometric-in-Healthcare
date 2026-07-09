# Mobile-Based Fingerprint Verification System for Patient Identification in Healthcare

A final-year project implementing a hospital-grade patient identification system using fingerprint biometrics. The system combines a Flutter mobile application, a Laravel REST API, and a Python-based fingerprint processing microservice to register and verify patients within controlled hospital premises.

---

## Service READMEs

| Service | README |
|---------|--------|
| Laravel REST API | [laravel/README.md](laravel/README.md) |
| Python Fingerprint Microservice | [python-service/README.md](python-service/README.md) |
| Flutter Mobile App | [mobile/README.md](mobile/README.md) |

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Repository Structure](#repository-structure)
4. [Prerequisites](#prerequisites)
5. [Installation](#installation)
   - [Backend — Laravel API](#backend--laravel-api)
   - [Fingerprint Service — Python / FastAPI](#fingerprint-service--python--fastapi)
   - [Mobile Application — Flutter](#mobile-application--flutter)
6. [Docker Deployment (VPS)](#docker-deployment-vps)
7. [Configuration](#configuration)
8. [Database Schema](#database-schema)
9. [API Reference](#api-reference)
10. [Role and Permission Model](#role-and-permission-model)
11. [Access Control](#access-control)
12. [Security Considerations](#security-considerations)
13. [Development Notes](#development-notes)

---

## System Overview

The system addresses the problem of patient misidentification in healthcare settings by providing a biometric-based identity verification workflow. Rather than relying on ID cards or verbal confirmation, nurses scan a patient's fingerprint at the point of care. The fingerprint is matched against stored templates to confirm identity before clinical decisions are made.

Core capabilities:

- **Patient registration** with demographic data and fingerprint enrollment
- **Real-time fingerprint verification** at the point of care
- **Role-based access control** with four distinct staff roles
- **Four-finger contactless capture** — a single hand photo is segmented into four finger crops and matched via a learned ONNX embedding (Ridgeformer), fusing per-finger scores instead of relying on a single contact-style fingerprint
- **Multi-hospital isolation** — each hospital's data is strictly partitioned
- **Geofencing and WiFi restriction** — the mobile app enforces on-premises usage, with a server-side fail-open/fail-closed policy for hospitals that haven't configured a perimeter yet
- **Audit logging** — all sensitive actions are recorded with actor, action, and timestamp
- **Edit request workflow** — nurses submit change requests that administrators approve or reject

---

## Architecture

```
┌─────────────────────────┐
│   Flutter Mobile App    │  Staff-facing UI (Android / iOS)
│  - Auto-trigger capture │
│  - Live quality ring    │
│  - GPS + WiFi gate      │
│  - --dart-define config │
└────────────┬────────────┘
             │ HTTPS / JSON
             ▼
┌─────────────────────────┐
│   Laravel 13 REST API   │  Primary application server
│  - Sanctum token auth   │
│  - Role middleware       │
│  - Hospital isolation   │
│  - Audit log service    │
│  - Face verify-confirm  │
│  - Accept/reject decision│  ← thresholds live here, not in Python
└────────────┬────────────┘
             │ Internal HTTP (X-Internal-Api-Key header)
             ▼
┌─────────────────────────┐
│  FastAPI Microservice   │  Biometric processing (not public-facing)
│  - OpenCV/minutiae FP   │
│  - ONNX embedding (hand)│  ← four-finger contactless matcher
│  - FAISS face search    │
│  - Liveness detection   │
│  - Index quarantine     │
└─────────────────────────┘
             │
             ▼
        MySQL 8 Database
```

The Python microservice is consumed exclusively by Laravel and is never exposed directly to the mobile client or the public internet. It holds no accept/reject thresholds itself — it only returns raw scores/templates; Laravel is the single source of truth for match decisions (`config/services.php`). Requests between Laravel and Python are authenticated with a shared internal API key (`X-Internal-Api-Key` / `INTERNAL_API_KEY`) — see [Configuration](#configuration).

---

## Repository Structure

```
BiH app/
├── laravel/                  Laravel 11 backend API
│   ├── app/
│   │   ├── Http/
│   │   │   ├── Controllers/
│   │   │   │   ├── Api/     API controllers (Auth, Patient, Fingerprint, Verification, …)
│   │   │   │   └── Web/     Admin web panel controllers
│   │   ├── Models/           Eloquent models (User, Patient, Fingerprint, Hospital, …)
│   │   ├── Policies/         Authorization policies
│   │   └── Services/         Business logic services
│   ├── database/
│   │   ├── migrations/       Database migrations (chronological)
│   │   └── schema.sql        Full schema dump
│   └── routes/
│       ├── api.php           REST API routes with role/rate-limit middleware
│       └── web.php           Admin panel routes
│
├── mobile/                   Flutter mobile application
│   └── lib/
│       ├── models/           Data models
│       ├── providers/        State management (Provider)
│       ├── screens/          UI screens
│       ├── services/         API and device service classes
│       ├── theme/            Application theme
│       └── widgets/          Reusable widget components
│
└── python-service/           FastAPI biometric microservice
    ├── app/
    │   ├── routes/           HTTP route handlers (health, fingerprint, hand, face)
    │   └── services/         Minutiae + ONNX embedding matchers, hand segmentation,
    │                         FAISS index, liveness detection
    ├── models/                contactless_embedding.onnx (~1.1GB, gitignored — see
    │                         Docker Deployment for how it reaches a VPS)
    ├── tools/                 Calibration scripts (calibrate_far_frr.py, ridgebase_eval.py, …)
    ├── quarantine/            Corrupt FAISS index backups (auto-created)
    ├── Dockerfile
    ├── requirements.txt
    └── run.py

docker-compose.yml            Compose stack: mysql + python-service + laravel
```

---

## Prerequisites

| Component | Version |
|-----------|---------|
| PHP | 8.3 or later |
| Composer | 2.x |
| Laravel | 13.x |
| MySQL | 8.0 or later |
| Python | 3.13 or later |
| Flutter | 3.x (stable channel) |
| Dart | 3.x |
| Docker + Docker Compose | Only needed for VPS/production deployment — not required for local dev (see [Docker Deployment](#docker-deployment-vps)) |

---

## Installation

### Backend — Laravel API

```bash
cd laravel

# Install PHP dependencies
composer install

# Copy environment file and configure values
cp .env.example .env
php artisan key:generate

# Run database migrations
php artisan migrate

# Create storage symlink (for file uploads)
php artisan storage:link

# Start the development server (--host=0.0.0.0 to allow LAN access, e.g. from web-admin on another device)
php artisan serve --host=0.0.0.0
```

The API will be available at `http://localhost:8000` (or `http://<your-lan-ip>:8000` for other devices on the network).

### Fingerprint Service — Python / FastAPI

```bash
cd python-service

# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate        # macOS / Linux
# venv\Scripts\activate         # Windows

# Install dependencies
pip install -r requirements.txt

# Start the service
python run.py
```

The microservice runs on `http://localhost:5001` by default. Interactive API documentation is available at `http://localhost:5001/docs`.

### Mobile Application — Flutter

```bash
cd mobile

# Fetch dependencies
flutter pub get

# Run on a connected device or emulator (override API URL if needed)
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000/api
```

The API base URL and WiFi bypass are controlled by `--dart-define` flags — not hardcoded in service files. See `lib/config/app_config.dart` and `mobile/README.md` for details.

---

## Docker Deployment (VPS)

Local development does **not** require Docker — the steps above (composer, php artisan serve, python run.py) are unaffected. Docker is only used for hosting the Laravel + Python + MySQL stack on a VPS.

```bash
# On the VPS, after cloning the repo:
cp laravel/.env.example laravel/.env               # fill in real values
cp python-service/.env.example python-service/.env  # fill in real values

docker compose up -d --build
```

Key points:

- **`laravel/Dockerfile`** — multi-stage build (composer install → `vite build` → `php:8.3-apache` runtime).
- **`python-service/Dockerfile`** — `python:3.13-slim` + OpenCV/onnxruntime system libraries.
- **`docker-compose.yml`** — wires `mysql`, `python-service`, and `laravel` together. `laravel` joins an external `proxy-net` network (for a reverse proxy such as Nginx Proxy Manager to terminate TLS) plus an internal-only network shared with `mysql`/`python-service`, which stay unreachable from outside the stack. If you're not using an external proxy network, remove the `proxy-net` entry and publish Laravel's port directly.
- **The 1.1GB ONNX model (`python-service/models/contactless_embedding.onnx`) is gitignored and bind-mounted, not baked into the image.** It must be transferred to the VPS separately before first run:
  ```bash
  rsync -avz --progress --partial python-service/models/contactless_embedding.onnx \
      <user>@<vps-host>:~/Biometric-in-Healthcare/python-service/models/
  ```
  `rsync` (not `scp`) is used so a dropped connection can resume rather than restart the transfer.
- **Production env flags** — `APP_ENV=production` / `APP_DEBUG=false` are set as `environment:` overrides directly in `docker-compose.yml` for the `laravel` service, so the container is always production-safe regardless of what `laravel/.env` contains (which stays `local`/`true` for local dev).
- **Seed demo/reference data** after first migration:
  ```bash
  docker compose exec laravel php artisan db:seed --class=HospitalSeeder
  ```

---

## Configuration

### Laravel `.env` (key values)

```env
APP_NAME="BiH Fingerprint System"
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=bih_db
DB_USERNAME=root
DB_PASSWORD=

# Python biometric microservice
PYTHON_SERVICE_URL=http://127.0.0.1:5001
PYTHON_SERVICE_API_KEY=          # must match INTERNAL_API_KEY on the Python side — required in production

# Single source of truth for the fingerprint accept/reject decision.
# Calibrate with python-service/tools/calibrate_far_frr.py.
FINGERPRINT_MATCH_THRESHOLD=32.0

# Fused four-finger (hand-slap) contactless threshold. Left unset until an
# embedding matcher is calibrated for your deployment — see
# python-service/tools/ridgebase_eval.py. While unset, hand verification
# returns advisory "needs_review" results and never auto-accepts.
FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD=

# When a hospital has neither GPS nor WiFi SSID configured, this decides the
# outcome. true = allow (useful for demos); false = deny (required in
# production so a misconfigured hospital fails closed, not open).
GEOFENCE_FAIL_OPEN=true

SANCTUM_STATEFUL_DOMAINS=localhost,localhost:3000
```

### Python service `.env` (key values)

```env
# Must match PYTHON_SERVICE_API_KEY on the Laravel side. Leaving this unset
# is fine for local dev only — a warning is logged and every endpoint
# (except /health) is left unauthenticated.
INTERNAL_API_KEY=

FINGERPRINT_MATCH_THRESHOLD=32.0
ENVIRONMENT=development   # set to "production" to disable /docs and /redoc
```

The default port (5001) is defined in `python-service/run.py`. Change the `port` argument if there is a conflict.

---

## Database Schema

The database models the following primary entities:

| Table | Purpose |
|-------|---------|
| `hospitals` | Multi-hospital tenancy; each record isolates a clinical site |
| `users` | Staff accounts with role and hospital assignment |
| `patients` | Demographic records registered per hospital |
| `fingerprints` | Processed ORB templates linked to patients; includes lock state |
| `face_templates` | Face embeddings per patient; oldest evicted when per-patient cap is reached |
| `verification_logs` | Timestamped record of every identification scan |
| `patient_edit_requests` | Nurse-submitted requests for demographic corrections |
| `audit_logs` | Immutable log of all sensitive system actions |

Foreign key constraints enforce referential integrity across all tables.

---

## API Reference

All API endpoints are prefixed with `/api`. Authentication uses Laravel Sanctum bearer tokens issued at login.

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Obtain a Sanctum token |
| POST | `/api/auth/logout` | Revoke the current token |
| GET | `/api/auth/me` | Retrieve the authenticated user profile |

### Patients

| Method | Endpoint | Minimum Role |
|--------|----------|--------------|
| GET | `/api/patients` | All roles |
| GET | `/api/patients/{id}` | All roles |
| POST | `/api/patients` | Nurse |
| PUT | `/api/patients/{id}` | Admin, Super Admin |
| DELETE | `/api/patients/{id}` | Admin, Super Admin |
| POST | `/api/patients/{id}/enroll` | Nurse, Admin |
| DELETE | `/api/patients/{id}/fingerprints/{fid}` | Admin, Super Admin |
| POST | `/api/patients/{id}/edit-requests` | Nurse |

### Fingerprint Pipeline

| Method | Endpoint | Description | Minimum Role |
|--------|----------|-------------|--------------|
| POST | `/api/fingerprint/upload` | Legacy base64 enrollment | Nurse, Admin |
| POST | `/api/fingerprint/register` | Enhanced enrollment pipeline | Nurse, Admin |
| POST | `/api/fingerprint/verify` | Direct patient verification | Nurse |
| POST | `/api/fingerprint/{id}/unlock` | Unlock locked record | Admin, Super Admin |

### Face Pipeline

| Method | Endpoint | Description | Minimum Role |
|--------|----------|-------------|--------------|
| POST | `/api/face/enroll` | Enroll face embedding for a patient | Nurse, Admin |
| POST | `/api/face/identify` | Identify patient by face (FAISS search) | Nurse |
| POST | `/api/face/verify-confirm` | Record manual staff confirmation with audit trail | Nurse |

### Four-Finger Contactless Pipeline

A single hand photo is segmented server-side into four finger crops (`python-service` `/process-hand`), each matched via a learned ONNX embedding, and the per-finger scores are fused into one decision (`/match-hand`). This replaces relying on a single contact-style fingerprint scan.

| Method | Endpoint | Description | Minimum Role |
|--------|----------|-------------|--------------|
| POST | `/api/patients/{patient}/enroll-hand` | Segment a hand photo and enroll one template per finger | Nurse, Admin |
| POST | `/api/verify/hand` | Verify a probe hand photo against enrolled candidates (fused score) | Nurse |

`verify/hand` is advisory (`needs_review`) until a learned contactless embedding matcher and calibrated `FINGERPRINT_CONTACTLESS_MATCH_THRESHOLD` are installed — it never auto-accepts on minutiae alone.

### Verification

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/verify` | **Deprecated** — hospital-wide 1:N fingerprint identification; emits RFC-8594 deprecation headers. Superseded by `/api/verify/multimodal`. |
| POST | `/api/verify/multimodal` | Multi-modal identification: face shortlist → fingerprint confirm. Keeps false-accept risk from growing with database size. |
| POST | `/api/verify/hand` | Four-finger fused verification (see [Four-Finger Contactless Pipeline](#four-finger-contactless-pipeline)) |
| GET | `/api/verify/logs` | View verification history |
| GET | `/api/verify/logs/{id}` | Single verification log detail |

### Administration

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET/POST/PUT/DELETE | `/api/users` | Staff account management (Admin, Super Admin) |
| GET | `/api/audit-logs` | System audit trail (Super Admin, Admin, Doctor) |
| GET/PUT | `/api/edit-requests` | Review queue for nurse-submitted edit requests |

### Rate Limits

| Endpoint group | Limit |
|----------------|-------|
| `/api/auth/login` | 10 requests per minute per IP |
| Fingerprint enrollment | 20 requests per minute per token |
| Fingerprint verification | 30 requests per minute per token |

---

## Role and Permission Model

The system defines four staff roles with progressively narrower clinical access:

| Role | Scope | Key Permissions |
|------|-------|----------------|
| `super_admin` | Cross-hospital | Hospital management, user management across sites, audit logs. No clinical data access. |
| `admin` | Own hospital | User management, patient demographic edits, edit request approval, fingerprint unlock, emergency enrollment |
| `doctor` | Own hospital | Read-only access to patient records, EHR data, verification logs, audit logs |
| `nurse` | Own hospital | Patient registration, fingerprint enrollment, real-time verification, submit edit requests |

Role enforcement is applied at the route level via `role:` middleware. Hospital isolation is enforced via a separate `hospital.access` middleware that compares the authenticated user's hospital against the requested resource.

---

## Access Control

### Geofencing (Mobile)

The Flutter application checks the device's GPS coordinates before permitting any clinical action. If the device is outside the configured hospital perimeter, the action is blocked at the client level.

### WiFi Restriction (Mobile)

The application uses the `network_info_plus` package to read the connected WiFi SSID. Only devices connected to the designated hospital network are permitted to proceed.

### Backend Validation

Client-side geofencing is a convenience control only. The Laravel backend independently validates the request context via the `geofence` middleware, which checks the device's GPS/WiFi against the hospital's configured perimeter (`GeofenceService`). Do not rely on mobile-side checks as a security boundary.

If a hospital has configured **neither** GPS coordinates nor a WiFi SSID, the outcome is governed by `GEOFENCE_FAIL_OPEN` (see [Configuration](#configuration)) — `true` allows the request through (useful for demos/unconfigured hospitals), `false` denies it. Production deployments should set this to `false` so an incomplete hospital record fails closed rather than silently running unrestricted.

---

## Security Considerations

- **Biometric templates, not images** — The system stores ORB/minutiae descriptors and learned embeddings (fingerprint/hand), and 512-dim embeddings (face) — not raw photographs. This limits biometric data exposure.
- **Internal service authentication** — Laravel ↔ Python calls carry a shared-secret header (`X-Internal-Api-Key` / `INTERNAL_API_KEY`). Must be set in production; if left blank the Python service logs a warning and accepts unauthenticated requests (acceptable for local dev only).
- **Token-based authentication** — Sanctum issues per-session tokens that are revoked on logout.
- **Input validation** — All API inputs are validated using Laravel Form Requests before reaching business logic.
- **Audit trail** — A dedicated `AuditLog` service records actor, action type, and affected resource for all sensitive operations, including manual face review confirmations.
- **Fingerprint locking** — Records that exceed a failed-match threshold are automatically locked and require administrator intervention to unlock.
- **FAISS index integrity** — 512-dim embedding validation prevents silent index corruption; corrupted index files are quarantined with a timestamp backup rather than discarded.
- **Transactional face enrollment** — The new face template row is persisted before the oldest is evicted, and FAISS calls are wrapped in the DB transaction so a Python-side failure rolls back the database.
- **HTTPS** — The API must be served over HTTPS in production. The `.env` `APP_URL` and Sanctum `STATEFUL_DOMAINS` must reflect the production domain.

---

## Development Notes

- The Python microservice is internal and must never be exposed on a public port. Locally, keep it bound to `127.0.0.1`. Under Docker, it has no `ports:` mapping at all — only `expose:` on the internal compose network — and additionally requires `X-Internal-Api-Key` once `INTERNAL_API_KEY`/`PYTHON_SERVICE_API_KEY` are set.
- The mobile app connects to the API using a base URL configured in the service layer. Update this value for each deployment target (development, staging, production).
- Database migrations are numbered chronologically. Run them in order using `php artisan migrate`. Do not modify existing migration files after they have been applied.
- The `super_admin` role is assigned via a dedicated migration and seeder; it is not selectable through the normal staff creation UI.
