<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    /**
     * GET /api/users
     * Admin only. Returns all users in the caller's hospital.
     */
    public function index(Request $request): JsonResponse
    {
        Gate::authorize('admin-only');

        $users = User::where('hospital_id', $request->user()->hospital_id)
            ->get();

        return response()->json(['users' => $users]);
    }

    /**
     * POST /api/users
     * Admin only.
     */
    public function store(Request $request): JsonResponse
    {
        Gate::authorize('admin-only');

        $data = $request->validate([
            'name'        => 'required|string|max:200',
            'username'    => 'required|string|max:80|unique:users',
            'email'       => 'required|email|unique:users',
            'password'    => 'required|string|min:8',
            'role'        => ['required', Rule::in(['admin', 'operator', 'doctor'])],
            'hospital_id' => 'required|integer|exists:hospitals,id',
        ]);

        $user = User::create($data);

        return response()->json(['user' => $user], 201);
    }

    /**
     * GET /api/users/{user}
     */
    public function show(Request $request, User $user): JsonResponse
    {
        // Operators can only view themselves; admins see anyone in their hospital
        if (! $request->user()->isAdmin() && $request->user()->id !== $user->id) {
            return response()->json(['error' => 'Forbidden.'], 403);
        }

        return response()->json(['user' => $user]);
    }

    /**
     * PUT /api/users/{user}
     */
    public function update(Request $request, User $user): JsonResponse
    {
        $isAdmin = $request->user()->isAdmin();

        if (! $isAdmin && $request->user()->id !== $user->id) {
            return response()->json(['error' => 'Forbidden.'], 403);
        }

        $rules = [
            'name'  => 'sometimes|string|max:200',
            'email' => ['sometimes', 'email', Rule::unique('users')->ignore($user->id)],
        ];

        // Only admins may change role / active status / hospital
        if ($isAdmin) {
            $rules['role']        = ['sometimes', Rule::in(['admin', 'operator', 'doctor'])];
            $rules['is_active']   = 'sometimes|boolean';
            $rules['hospital_id'] = 'sometimes|integer|exists:hospitals,id';
        }

        $user->update($request->validate($rules));

        return response()->json(['user' => $user->fresh()]);
    }

    /**
     * DELETE /api/users/{user}
     * Admin only — soft-deactivates the account.
     */
    public function destroy(Request $request, User $user): JsonResponse
    {
        Gate::authorize('admin-only');

        $user->update(['is_active' => false]);

        return response()->json(['message' => 'User deactivated.']);
    }
}
