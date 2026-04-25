<?php

use App\Http\Controllers\Web\AuthController;
use App\Http\Controllers\Web\DashboardController;
use Illuminate\Support\Facades\Route;

Route::get('/', fn () => redirect()->route('dashboard.index'));

Route::get('/login', [AuthController::class, 'showLogin'])->name('login');
Route::post('/login', [AuthController::class, 'login'])->name('login.post');
Route::post('/logout', [AuthController::class, 'logout'])->name('logout');

Route::middleware('auth')->prefix('dashboard')->name('dashboard.')->group(function () {
    Route::get('/',                       [DashboardController::class, 'index'])->name('index');
    Route::get('/patients',               [DashboardController::class, 'patients'])->name('patients');
    Route::get('/patients/{patient}',     [DashboardController::class, 'patientShow'])->name('patients.show');
    Route::get('/logs',                   [DashboardController::class, 'logs'])->name('logs');
});
