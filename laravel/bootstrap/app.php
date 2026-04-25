<?php

use App\Http\Middleware\CheckHospitalAccess;
use App\Http\Middleware\EnsureActiveUser;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        apiPrefix: 'api',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Reject requests from deactivated accounts even with a valid token
        $middleware->appendToGroup('api', EnsureActiveUser::class);

        // Sanctum stateful API support (cookie-based for same-domain clients)
        $middleware->statefulApi();

        // Named alias — used in routes/api.php as 'hospital.access'
        $middleware->alias([
            'hospital.access' => CheckHospitalAccess::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Always return JSON for api/* routes — no HTML error pages
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request, \Throwable $e) => $request->is('api/*')
        );
    })
    ->create();
