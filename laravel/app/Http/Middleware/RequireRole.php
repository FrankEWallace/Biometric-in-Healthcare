<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Usage: ->middleware('role:nurse,admin')
 * Passes if the authenticated user's role matches any of the listed roles.
 */
class RequireRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if (! $user || ! in_array($user->role, $roles, true)) {
            return response()->json(['error' => 'Forbidden. Insufficient role.'], 403);
        }

        return $next($request);
    }
}
