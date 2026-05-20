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
6. [Configuration](#configuration)
7. [Database Schema](#database-schema)
8. [API Reference](#api-reference)
9. [Role and Permission Model](#role-and-permission-model)
10. [Access Control](#access-control)
11. [Security Considerations](#security-considerations)
12. [Development Notes](#development-notes)

---

## System Overview

The system addresses the problem of patient misidentification in healthcare settings by providing a biometric-based identity verification workflow. Rather than relying on ID cards or verbal confirmation, nurses scan a patient's fingerprint at the point of care. The fingerprint is matched against stored templates to confirm identity before clinical decisions are made.

Core capabilities:

- **Patient registration** with demographic data and fingerprint enrollment
- **Real-time fingerprint verification** at the point of care
- **Role-based access control** with four distinct staff roles
- **Multi-hospital isolation** — each hospital's data is strictly partitioned
- **Geofencing and WiFi restriction** — the mobile app enforces on-premises usage
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
│   Laravel 11 REST API   │  Primary application server
│  - Sanctum token auth   │
│  - Role middleware       │
│  - Hospital isolation   │
│  - Audit log service    │
│  - Face verify-confirm  │
└────────────┬────────────┘
             │ Internal HTTP (localhost:5001)
             ▼
┌─────────────────────────┐
│  FastAPI Microservice   │  Biometric processing (not public-facing)
│  - OpenCV fingerprint   │
│  - FAISS face search    │
│  - Liveness detection   │
│  - Index quarantine     │
└─────────────────────────┘
             │
             ▼
        MySQL 8 Database
```

The Python microservice is consumed exclusively by Laravel. It is never exposed directly to the mobile client or the public internet.

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
    │   ├── routes/           HTTP route handlers (health, fingerprint, face)
    │   └── services/         OpenCV processing, FAISS index, liveness detection
    ├── quarantine/           Corrupt FAISS index backups (auto-created)
    ├── requirements.txt
    └── run.py
```

---

## Prerequisites

| Component | Version |
|-----------|---------|
| PHP | 8.2 or later |
| Composer | 2.x |
| Laravel | 11.x |
| MySQL | 8.0 or later |
| Python | 3.11 or later |
| Flutter | 3.x (stable channel) |
| Dart | 3.x |

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

# Start the development server
php artisan serve
```

The API will be available at `http://localhost:8000`.

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

## Configuration

### Laravel `.env` (key values)

```env
APP_NAME="BiH Fingerprint System"
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=bih_fingerprint
DB_USERNAME=root
DB_PASSWORD=

# Address of the Python fingerprint microservice
FINGERPRINT_SERVICE_URL=http://localhost:5001

SANCTUM_STATEFUL_DOMAINS=localhost,localhost:3000
```

### Python service port

The default port is defined in `python-service/run.py`. Change the `port` argument if there is a conflict.

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

### Verification

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/verify` | Identification scan (nurse only) |
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

Client-side geofencing is a convenience control only. The Laravel backend independently validates the request context where applicable. Do not rely on mobile-side checks as a security boundary.

---

## Security Considerations

- **Biometric templates, not images** — The system stores ORB minutiae descriptors (fingerprint) and 512-dim embeddings (face), not raw photographs. This limits biometric data exposure.
- **Token-based authentication** — Sanctum issues per-session tokens that are revoked on logout.
- **Input validation** — All API inputs are validated using Laravel Form Requests before reaching business logic.
- **Audit trail** — A dedicated `AuditLog` service records actor, action type, and affected resource for all sensitive operations, including manual face review confirmations.
- **Fingerprint locking** — Records that exceed a failed-match threshold are automatically locked and require administrator intervention to unlock.
- **FAISS index integrity** — 512-dim embedding validation prevents silent index corruption; corrupted index files are quarantined with a timestamp backup rather than discarded.
- **Transactional face enrollment** — The new face template row is persisted before the oldest is evicted, and FAISS calls are wrapped in the DB transaction so a Python-side failure rolls back the database.
- **HTTPS** — The API must be served over HTTPS in production. The `.env` `APP_URL` and Sanctum `STATEFUL_DOMAINS` must reflect the production domain.

---

## Development Notes

- The Python microservice is internal and should not be exposed on a public port. In production, bind it to `127.0.0.1` only and access it from Laravel via localhost.
- The mobile app connects to the API using a base URL configured in the service layer. Update this value for each deployment target (development, staging, production).
- Database migrations are numbered chronologically. Run them in order using `php artisan migrate`. Do not modify existing migration files after they have been applied.
- The `super_admin` role is assigned via a dedicated migration and seeder; it is not selectable through the normal staff creation UI.
