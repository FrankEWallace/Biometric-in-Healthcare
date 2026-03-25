<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Reject requests from deactivated user accounts even if their token
 * is still technically valid.
 */
class EnsureActiveUser
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user() && ! $request->user()->is_active) {
            return response()->json(['error' => 'Account is disabled.'], 403);
        }

        return $next($request);
    }
}
