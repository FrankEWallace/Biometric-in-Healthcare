<?php

use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\FingerprintController;
use App\Http\Controllers\Api\PatientController;
use App\Http\Controllers\Api\PatientEditRequestController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\VerificationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| BiH Patient Fingerprint System — API Routes
|--------------------------------------------------------------------------
|
| Role matrix enforced via 'role:x,y' middleware:
|
|   super_admin — cross-hospital management, no clinical data
|   admin       — own-hospital management, emergency enrollment
|   doctor      — read-only clinical (EHR, insurance, patients, logs)
|   nurse       — fingerprint verification, patient registration, enrollment
|
| Rate limits:
|   verify    — 30 req/min per token
|   enroll    — 20 req/min per token
|   login     — 10 req/min per IP
|
*/

// ── Public ────────────────────────────────────────────────────────────────────
Route::prefix('auth')->middleware('throttle:10,1')->group(function () {
    Route::post('login', [AuthController::class, 'login']);
});

// ── Authenticated ─────────────────────────────────────────────────────────────
Route::middleware('auth:sanctum')->group(function () {

    // Auth (all roles)
    Route::prefix('auth')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me',      [AuthController::class, 'me']);
    });

    // ── Patients ──────────────────────────────────────────────────────────────
    Route::prefix('patients')->middleware('hospital.access')->group(function () {

        // All roles can list and view patients
        Route::get('/',          [PatientController::class, 'index']);
        Route::get('/{patient}', [PatientController::class, 'show']);

        // Nurse: register new patients
        Route::post('/', [PatientController::class, 'store'])
             ->middleware('role:nurse');

        // Admin/super_admin: direct demographic edit
        Route::put('/{patient}', [PatientController::class, 'update'])
             ->middleware('role:admin,super_admin');

        // Admin/super_admin: deactivate patient
        Route::delete('/{patient}', [PatientController::class, 'destroy'])
             ->middleware('role:admin,super_admin');

        // Nurse + admin (emergency): fingerprint enrollment
        Route::post('/{patient}/enroll', [PatientController::class, 'enroll'])
             ->middleware(['role:nurse,admin', 'throttle:20,1']);

        // Admin/super_admin: remove a fingerprint record
        Route::delete('/{patient}/fingerprints/{fingerprint}', [PatientController::class, 'removeFingerprint'])
             ->middleware('role:admin,super_admin');

        // Nurse: submit a demographic edit request
        Route::post('/{patient}/edit-requests', [PatientEditRequestController::class, 'store'])
             ->middleware('role:nurse');
    });

    // ── Edit Request Review Queue ─────────────────────────────────────────────
    Route::prefix('edit-requests')->group(function () {

        // Admin/super_admin: review queue
        Route::get('/',                      [PatientEditRequestController::class, 'index'])
             ->middleware('role:admin,super_admin');
        Route::put('/{editRequest}/approve', [PatientEditRequestController::class, 'approve'])
             ->middleware('role:admin,super_admin');
        Route::put('/{editRequest}/reject',  [PatientEditRequestController::class, 'reject'])
             ->middleware('role:admin,super_admin');

        // Nurse: cancel own pending request
        Route::put('/{editRequest}/cancel', [PatientEditRequestController::class, 'cancel'])
             ->middleware('role:nurse');
    });

    // ── Fingerprint Pipelines ─────────────────────────────────────────────────
    Route::prefix('fingerprint')->middleware('hospital.access')->group(function () {

        // Legacy base64 pipeline — nurse + admin (emergency)
        Route::post('upload', [FingerprintController::class, 'upload'])
             ->middleware(['role:nurse,admin', 'throttle:20,1']);

        // Enhanced pipeline — nurse + admin (emergency)
        Route::post('register', [FingerprintController::class, 'register'])
             ->middleware(['role:nurse,admin', 'throttle:20,1']);

        // Direct patient verification — nurse only
        Route::post('verify', [FingerprintController::class, 'verify'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Admin/super_admin: unlock a locked fingerprint record
        Route::post('/{fingerprint}/unlock', [FingerprintController::class, 'unlock'])
             ->middleware('role:admin,super_admin');
    });

    // ── Hospital-wide Verification ────────────────────────────────────────────
    Route::prefix('verify')->middleware('hospital.access')->group(function () {

        // Identification scan — nurse only
        Route::post('/', [VerificationController::class, 'verify'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Logs — all roles; nurse sees own only, doctor sees patient-centric
        Route::get('/logs',       [VerificationController::class, 'logs']);
        Route::get('/logs/{log}', [VerificationController::class, 'showLog']);
    });

    // ── User Management ───────────────────────────────────────────────────────
    Route::prefix('users')->middleware('role:admin,super_admin')->group(function () {
        Route::get('/',          [UserController::class, 'index']);
        Route::post('/',         [UserController::class, 'store']);
        Route::get('/{user}',    [UserController::class, 'show']);
        Route::put('/{user}',    [UserController::class, 'update']);
        Route::delete('/{user}', [UserController::class, 'destroy']);
    });

    // ── Audit Logs ────────────────────────────────────────────────────────────
    Route::get('/audit-logs', [AuditLogController::class, 'index'])
         ->middleware('role:super_admin,admin,doctor');
});
