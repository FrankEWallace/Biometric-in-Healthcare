<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * POST /api/auth/login
     * { "username": "...", "password": "..." }
     */
    public function login(Request $request): JsonResponse
    {
        $request->validate([
            'username' => 'required|string',
            'password' => 'required|string',
        ]);

        $user = User::where('username', $request->username)->first();

        if (! $user || ! Auth::attempt(['username' => $request->username, 'password' => $request->password])) {
            throw ValidationException::withMessages([
                'username' => ['Invalid credentials.'],
            ]);
        }

        if (! $user->is_active) {
            return response()->json(['error' => 'Account is disabled.'], 403);
        }

        // Revoke old tokens and issue a fresh one
        $user->tokens()->delete();
        $token = $user->createToken('api-token', ['*'], now()->addHours(8))->plainTextToken;

        return response()->json([
            'token' => $token,
            'user'  => $this->userPayload($user),
        ]);
    }

    /**
     * POST /api/auth/logout
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();
        return response()->json(['message' => 'Logged out.']);
    }

    /**
     * GET /api/auth/me
     */
    public function me(Request $request): JsonResponse
    {
        return response()->json(['user' => $this->userPayload($request->user())]);
    }

    // ------------------------------------------------------------------

    private function userPayload(User $user): array
    {
        return [
            'id'          => $user->id,
            'name'        => $user->name,
            'username'    => $user->username,
            'email'       => $user->email,
            'role'        => $user->role,
            'hospital_id' => $user->hospital_id,
        ];
    }
}
