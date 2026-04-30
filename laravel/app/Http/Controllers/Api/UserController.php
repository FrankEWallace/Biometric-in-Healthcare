<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    /**
     * GET /api/users
     * super_admin: all users (filterable by hospital_id)
     * admin: own hospital users only
     */
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', User::class);

        $query = $request->user()->isSuperAdmin()
            ? User::query()
            : User::where('hospital_id', $request->user()->hospital_id);

        if ($hospitalId = $request->integer('hospital_id')) {
            $query->where('hospital_id', $hospitalId);
        }

        return response()->json(['users' => $query->get()]);
    }

    /**
     * POST /api/users
     */
    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', User::class);

        $allowedRoles = ['admin', 'nurse', 'doctor'];
        if ($request->user()->isSuperAdmin()) {
            $allowedRoles[] = 'super_admin';
        }

        $data = $request->validate([
            'name'        => 'required|string|max:200',
            'username'    => 'required|string|max:80|unique:users',
            'email'       => 'required|email|unique:users',
            'password'    => 'required|string|min:8',
            'role'        => ['required', Rule::in($allowedRoles)],
            'hospital_id' => 'required|integer|exists:hospitals,id',
        ]);

        // Hospital admin can only create users in their own hospital
        $hospitalId = $request->user()->isSuperAdmin()
            ? $data['hospital_id']
            : $request->user()->hospital_id;

        $user = User::create([
            'name'        => $data['name'],
            'username'    => $data['username'],
            'email'       => $data['email'],
            'password'    => $data['password'],
            'hospital_id' => $hospitalId,
        ]);
        $user->role = $data['role'];
        $user->is_active = true;
        $user->save();

        AuditLog::record($request, AuditLog::ACTION_USER_CREATED, null, null, null, [
            'created_user_id'   => $user->id,
            'created_user_role' => $user->role,
        ]);

        return response()->json(['user' => $user], 201);
    }

    /**
     * GET /api/users/{user}
     */
    public function show(Request $request, User $user): JsonResponse
    {
        $this->authorize('view', $user);
        return response()->json(['user' => $user]);
    }

    /**
     * PUT /api/users/{user}
     */
    public function update(Request $request, User $user): JsonResponse
    {
        $this->authorize('update', $user);

        $caller  = $request->user();
        $isAdmin = $caller->isAnyAdmin();

        $rules = [
            'name'  => 'sometimes|string|max:200',
            'email' => ['sometimes', 'email', Rule::unique('users')->ignore($user->id)],
        ];

        if ($isAdmin) {
            $allowedRoles = ['admin', 'nurse', 'doctor'];
            if ($caller->isSuperAdmin()) {
                $allowedRoles[] = 'super_admin';
            }

            $rules['role']      = ['sometimes', Rule::in($allowedRoles)];
            $rules['is_active'] = 'sometimes|boolean';

            if ($caller->isSuperAdmin()) {
                $rules['hospital_id'] = 'sometimes|integer|exists:hospitals,id';
            }
        }

        $validated = $request->validate($rules);

        // Safe fields go through fill(); privileged fields set explicitly
        $user->fill(array_intersect_key($validated, array_flip(['name', 'email'])));
        if (array_key_exists('role', $validated))        $user->role        = $validated['role'];
        if (array_key_exists('is_active', $validated))   $user->is_active   = $validated['is_active'];
        if (array_key_exists('hospital_id', $validated)) $user->hospital_id = $validated['hospital_id'];
        $user->save();

        return response()->json(['user' => $user->fresh()]);
    }

    /**
     * DELETE /api/users/{user} — soft-deactivates the account
     */
    public function destroy(Request $request, User $user): JsonResponse
    {
        $this->authorize('delete', $user);

        $user->is_active = false;
        $user->save();

        AuditLog::record($request, AuditLog::ACTION_USER_DEACTIVATED, null, null, null, [
            'deactivated_user_id'   => $user->id,
            'deactivated_user_role' => $user->role,
        ]);

        return response()->json(['message' => 'User deactivated.']);
    }
}
