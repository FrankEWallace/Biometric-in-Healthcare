<?php

use App\Http\Controllers\Web\AuthController;
use App\Http\Controllers\Web\DashboardController;
use Illuminate\Support\Facades\Route;

Route::get('/', fn () => redirect()->route('dashboard.index'));

Route::get('/login',  [AuthController::class, 'showLogin'])->name('login');
Route::post('/login', [AuthController::class, 'login'])->name('login.post');
Route::post('/logout', [AuthController::class, 'logout'])->name('logout');

Route::middleware('auth')->prefix('dashboard')->name('dashboard.')->group(function () {

    // ── Overview (role-aware) ─────────────────────────────────────────────────
    Route::get('/', [DashboardController::class, 'index'])->name('index');

    // ── Patients (all roles) ──────────────────────────────────────────────────
    Route::get('/patients',           [DashboardController::class, 'patients'])->name('patients');
    Route::get('/patients/{patient}', [DashboardController::class, 'patientShow'])->name('patients.show');

    // ── Verification Logs (all roles) ─────────────────────────────────────────
    Route::get('/logs', [DashboardController::class, 'logs'])->name('logs');

    // ── Edit Requests (admin / super_admin) ───────────────────────────────────
    Route::get('/edit-requests',                        [DashboardController::class, 'editRequests'])->name('edit-requests');
    Route::post('/edit-requests/{id}/approve',          [DashboardController::class, 'approveEditRequest'])->name('edit-requests.approve');
    Route::post('/edit-requests/{id}/reject',           [DashboardController::class, 'rejectEditRequest'])->name('edit-requests.reject');

    // ── Staff Management (admin / super_admin) ────────────────────────────────
    Route::get('/users',                                [DashboardController::class, 'users'])->name('users');
    Route::post('/users/{user}/deactivate',             [DashboardController::class, 'deactivateUser'])->name('users.deactivate');
    Route::post('/users/{user}/activate',               [DashboardController::class, 'activateUser'])->name('users.activate');

    // ── Audit Logs (admin / super_admin / doctor) ─────────────────────────────
    Route::get('/audit-logs', [DashboardController::class, 'auditLogs'])->name('audit-logs');
});
