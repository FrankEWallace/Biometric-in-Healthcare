<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\FingerprintController;
use App\Http\Controllers\Api\PatientController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\VerificationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| BiH Patient Fingerprint System — API Routes
|--------------------------------------------------------------------------
|
| All routes are prefixed with /api automatically by Laravel.
|
| Role matrix:
|   admin    — full access
|   nurse    — verify, enroll, view patients
|   doctor   — read-only on patients + logs
|
| Rate limits:
|   verify endpoint — 30 attempts / minute per token (brute-force protection)
|   enroll endpoint — 20 attempts / minute per token
|   login           — 10 attempts / minute per IP
|
*/

// ------------------------------------------------------------------
// Public
// ------------------------------------------------------------------
Route::prefix('auth')->middleware('throttle:10,1')->group(function () {
    Route::post('login', [AuthController::class, 'login']);
});

// ------------------------------------------------------------------
// Authenticated
// ------------------------------------------------------------------
Route::middleware('auth:sanctum')->group(function () {

    // Auth
    Route::prefix('auth')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me',      [AuthController::class, 'me']);
    });

    // Patients
    Route::prefix('patients')->middleware('hospital.access')->group(function () {
        Route::get('/',    [PatientController::class, 'index']);
        Route::post('/',   [PatientController::class, 'store']);
        Route::get('/{patient}',    [PatientController::class, 'show']);
        Route::put('/{patient}',    [PatientController::class, 'update']);
        Route::delete('/{patient}', [PatientController::class, 'destroy']);

        Route::post(
            '/{patient}/enroll',
            [PatientController::class, 'enroll']
        )->middleware('throttle:20,1');

        Route::delete(
            '/{patient}/fingerprints/{fingerprint}',
            [PatientController::class, 'removeFingerprint']
        );
    });

    // Fingerprint endpoints
    Route::prefix('fingerprint')->middleware('hospital.access')->group(function () {
        // Legacy — base64 pipeline (kept for VerificationController)
        Route::post('upload', [FingerprintController::class, 'upload'])
             ->middleware('throttle:20,1');

        // Enhanced pipeline — multipart image → full preprocessing + ORB
        Route::post('register', [FingerprintController::class, 'register'])
             ->middleware('throttle:20,1');

        // Direct patient verification (known patient ID)
        Route::post('verify', [FingerprintController::class, 'verify'])
             ->middleware('throttle:30,1');
    });

    // Fingerprint verification — tighter rate limit (30 req/min)
    Route::prefix('verify')->group(function () {
        Route::post('/', [VerificationController::class, 'verify'])
             ->middleware('throttle:30,1');

        Route::get('/logs',         [VerificationController::class, 'logs']);
        Route::get('/logs/{log}',   [VerificationController::class, 'showLog']);
    });

    // User management
    Route::prefix('users')->group(function () {
        Route::get('/',          [UserController::class, 'index']);
        Route::post('/',         [UserController::class, 'store']);
        Route::get('/{user}',    [UserController::class, 'show']);
        Route::put('/{user}',    [UserController::class, 'update']);
        Route::delete('/{user}', [UserController::class, 'destroy']);
    });
});
