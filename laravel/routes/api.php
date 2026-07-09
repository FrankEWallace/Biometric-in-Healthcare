<?php

use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\DeviceController;
use App\Http\Controllers\Api\HospitalController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\FaceController;
use App\Http\Controllers\Api\FingerprintController;
use App\Http\Controllers\Api\PatientController;
use App\Http\Controllers\Api\PatientEditRequestController;
use App\Http\Controllers\Api\SupervisorOverrideController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\VerificationController;
use App\Http\Controllers\Api\VisitController;
use App\Http\Controllers\Api\VisitStageController;
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
        Route::post('logout',        [AuthController::class, 'logout']);
        Route::get('me',             [AuthController::class, 'me']);
        Route::put('profile',        [AuthController::class, 'updateProfile']);
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
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

        // Nurse + admin: four-finger ("hand slap") enrollment
        Route::post('/{patient}/enroll-hand', [PatientController::class, 'enrollHand'])
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

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
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

        // Enhanced pipeline — nurse + admin (emergency)
        Route::post('register', [FingerprintController::class, 'register'])
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

        // Multi-capture gallery enrollment (up to 3 captures/finger) — nurse + admin
        Route::post('enroll-gallery', [FingerprintController::class, 'enrollGallery'])
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

        // Direct patient verification — nurse only
        Route::post('verify', [FingerprintController::class, 'verify'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Passive liveness check (optical flow) — nurse + admin
        Route::post('liveness-check', [FingerprintController::class, 'livenessCheck'])
             ->middleware(['role:nurse,admin', 'throttle:60,1']);

        // Admin/super_admin: unlock a locked fingerprint record
        Route::post('/{fingerprint}/unlock', [FingerprintController::class, 'unlock'])
             ->middleware('role:admin,super_admin');
    });

    // ── Hospital-wide Verification ────────────────────────────────────────────
    Route::prefix('verify')->middleware('hospital.access')->group(function () {

        // DEPRECATED: hospital-wide 1:N fingerprint identification.
        // Superseded by POST /api/verify/multimodal (face shortlist →
        // fingerprint confirm), which keeps false-accept risk from growing
        // with the patient database size. Kept temporarily for backward
        // compatibility; emits RFC-8594 deprecation headers. Nurse only.
        Route::post('/', [VerificationController::class, 'verify'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Multi-modal identification (face shortlist → fingerprint confirm) — nurse only
        Route::post('/multimodal', [VerificationController::class, 'verifyMultimodal'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Four-finger ("hand slap") fused verification — nurse only.
        // Advisory (needs_review) until a learned contactless embedding matcher
        // + calibrated threshold are installed; never auto-accepts on minutiae.
        Route::post('/hand', [VerificationController::class, 'verifyHand'])
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

    // ── Facial Recognition ────────────────────────────────────────────────────
    Route::prefix('face')->middleware('hospital.access')->group(function () {

        // Enroll a face template — nurse + admin (emergency)
        Route::post('enroll', [FaceController::class, 'enroll'])
             ->middleware(['role:nurse,admin', 'geofence', 'throttle:20,1']);

        // Hospital-wide face identification — nurse only
        Route::post('verify', [FaceController::class, 'verify'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Record staff manual confirmation of a borderline match — nurse only
        Route::post('verify-confirm', [FaceController::class, 'confirmReview'])
             ->middleware(['role:nurse', 'throttle:30,1']);

        // Rebuild FAISS index from all active templates — admin only
        Route::post('rebuild-index', [FaceController::class, 'rebuildIndex'])
             ->middleware(['role:admin', 'throttle:5,1']);
    });

    // ── Patient Visit Lifecycle ───────────────────────────────────────────────
    Route::prefix('visits')->middleware('hospital.access')->group(function () {

        // All roles: list visits and search patients
        Route::get('/',               [VisitController::class, 'index']);
        Route::get('/patient-search', [VisitController::class, 'patientSearch']);
        Route::get('/{visit}',        [VisitController::class, 'show']);

        // Clerk only: open / close / reopen
        Route::post('/',                    [VisitController::class, 'store'])
             ->middleware('role:clerk');
        Route::put('/{visit}/close',        [VisitController::class, 'close'])
             ->middleware('role:clerk');
        Route::put('/{visit}/reopen',       [VisitController::class, 'reopen'])
             ->middleware('role:clerk');

        // Stage verification — role enforcement is handled inside the controller
        Route::post('/{visit}/stages/{stage}/verify', [VisitStageController::class, 'verify'])
             ->middleware('throttle:30,1');

        // Stage data submission (simulated EMR) — role enforcement inside controller
        Route::put('/{visit}/stages/{stage}/data', [VisitStageController::class, 'updateData']);
    });

    // ── Stage Queue ───────────────────────────────────────────────────────────
    Route::get('/queue', [VisitStageController::class, 'queue'])
         ->middleware('hospital.access');

    // ── Supervisor Overrides ──────────────────────────────────────────────────
    Route::prefix('supervisor-overrides')->middleware('hospital.access')->group(function () {

        Route::get('/',                          [SupervisorOverrideController::class, 'index']);
        Route::post('/',                         [SupervisorOverrideController::class, 'store']);
        Route::put('/{override}/resolve',        [SupervisorOverrideController::class, 'resolve'])
             ->middleware('role:admin,doctor,nurse');
    });

    // ── Hospitals ─────────────────────────────────────────────────────────────
    // All roles: list active hospitals (used by Flutter for geofencing)
    Route::get('/hospitals',            [HospitalController::class, 'index']);
    Route::get('/hospitals/{hospital}', [HospitalController::class, 'show']);

    // super_admin: full CRUD; admin: update own hospital GPS/WiFi only
    Route::post('/hospitals',               [HospitalController::class, 'store'])
         ->middleware('role:super_admin');
    Route::put('/hospitals/{hospital}',     [HospitalController::class, 'update'])
         ->middleware('role:super_admin,admin');
    Route::delete('/hospitals/{hospital}',  [HospitalController::class, 'destroy'])
         ->middleware('role:super_admin');

    // ── Audit Logs ────────────────────────────────────────────────────────────
    Route::get('/audit-logs', [AuditLogController::class, 'index'])
         ->middleware('role:super_admin,admin,doctor');

    // ── Devices (read-only inventory derived from audit logs) ────────────────
    Route::get('/devices', [DeviceController::class, 'index'])
         ->middleware('role:super_admin,admin');
});
