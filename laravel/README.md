# BiH Fingerprint System — Laravel Backend

Laravel 11 REST API for the Mobile-Based Fingerprint Verification System for Patient Identification in Healthcare.

---

## Overview

This service is the primary application server. It handles authentication, role-based access control, patient records, fingerprint enrollment orchestration, and verification logging. Fingerprint image processing is delegated to the Python FastAPI microservice; this backend stores and matches the resulting feature descriptors.

---

## Requirements

| Dependency | Version |
|------------|---------|
| PHP | 8.2+ |
| Composer | 2.x |
| MySQL | 8.0+ |
| Python microservice | running on `localhost:5001` |

---

## Setup

```bash
# Install dependencies
composer install

# Configure environment
cp .env.example .env
php artisan key:generate

# Run migrations
php artisan migrate

# (Optional) Seed demo data
php artisan db:seed

# Create storage symlink
php artisan storage:link

# Start development server
php artisan serve
```

API available at `http://localhost:8000/api`.

---

## Environment Variables

Key values to configure in `.env`:

```env
APP_NAME="BiH Fingerprint System"
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=bih_fingerprint
DB_USERNAME=root
DB_PASSWORD=

# Internal address of the Python fingerprint microservice
FINGERPRINT_SERVICE_URL=http://localhost:5001

SANCTUM_STATEFUL_DOMAINS=localhost,localhost:3000
```

---

## Directory Structure

```
laravel/
├── app/
│   ├── Http/
│   │   ├── Controllers/Api/     API route controllers
│   │   ├── Controllers/Web/     Admin panel controllers
│   │   ├── Middleware/          role, hospital.access, geofence
│   │   └── Requests/            Form request validation classes
│   ├── Models/                  Eloquent models
│   ├── Policies/                Authorization policies
│   └── Services/                Business logic (AuditLog, Fingerprint, …)
├── database/
│   ├── migrations/              Chronological schema migrations
│   └── schema.sql               Full schema dump
└── routes/
    ├── api.php                  REST API routes
    └── web.php                  Admin panel routes
```

---

## Authentication

Laravel Sanctum token-based authentication. Tokens are issued on login and revoked on logout.

```
POST /api/auth/login    →  { token }
POST /api/auth/logout
GET  /api/auth/me
```

---

## Role Model

| Role | Scope | Description |
|------|-------|-------------|
| `super_admin` | Cross-hospital | Hospital and user management; no clinical data |
| `admin` | Own hospital | User management, demographic edits, edit-request approval, emergency enrollment |
| `doctor` | Own hospital | Read-only access to patients, EHR, verification logs, audit trail |
| `nurse` | Own hospital | Patient registration, fingerprint enrollment and verification |

Role enforcement is applied at the route level via `role:` middleware. Hospital isolation is enforced by a separate `hospital.access` middleware.

---

## API Endpoints

All endpoints are prefixed with `/api` and require a Sanctum bearer token unless noted.

### Patients

| Method | Endpoint | Min Role |
|--------|----------|----------|
| GET | `/patients` | All |
| GET | `/patients/{id}` | All |
| POST | `/patients` | Nurse |
| PUT | `/patients/{id}` | Admin |
| DELETE | `/patients/{id}` | Admin |
| POST | `/patients/{id}/enroll` | Nurse, Admin |
| DELETE | `/patients/{id}/fingerprints/{fid}` | Admin |
| POST | `/patients/{id}/edit-requests` | Nurse |

### Fingerprint

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/fingerprint/register` | Enrollment pipeline (calls Python service) |
| POST | `/fingerprint/verify` | Direct patient verification |
| POST | `/fingerprint/{id}/unlock` | Unlock locked fingerprint record |

### Verification

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/verify` | Identification scan |
| GET | `/verify/logs` | Verification history |
| GET | `/verify/logs/{id}` | Single log detail |

### Administration

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET/POST/PUT/DELETE | `/users` | Staff account management |
| GET | `/audit-logs` | System audit trail |
| GET/PUT | `/edit-requests` | Nurse-submitted demographic change requests |

### Rate Limits

| Group | Limit |
|-------|-------|
| `/auth/login` | 10 req/min per IP |
| Fingerprint enrollment | 20 req/min per token |
| Fingerprint verification | 30 req/min per token |

---

## Database Tables

| Table | Purpose |
|-------|---------|
| `hospitals` | Multi-hospital tenancy |
| `users` | Staff accounts |
| `patients` | Demographic records |
| `fingerprints` | ORB feature templates linked to patients |
| `verification_logs` | Every identification scan |
| `patient_edit_requests` | Nurse-submitted demographic change requests |
| `audit_logs` | Immutable action audit trail |

---

## Security Notes

- Fingerprint **templates** are stored, not raw images (ORB descriptors via Python service).
- All inputs validated via Laravel Form Requests before reaching business logic.
- Failed fingerprint matches beyond the threshold automatically lock the record.
- `AuditLogService` records actor, action, and affected resource for all sensitive operations.
- In production, serve over HTTPS and bind the Python microservice to `127.0.0.1` only.

---

## Related Services

- `../python-service/` — FastAPI fingerprint processing microservice
- `../mobile/` — Flutter mobile application
