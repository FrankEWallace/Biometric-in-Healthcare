<?php

namespace App\Policies;

use App\Models\Patient;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class PatientPolicy
{
    // All roles can list/view patients
    public function viewAny(User $user): bool
    {
        return true;
    }

    public function view(User $user, Patient $patient): Response|bool
    {
        if ($user->isSuperAdmin()) return true;
        if ($patient->hospital_id !== $user->hospital_id) {
            return Response::denyWithStatus(404);
        }
        return true;
    }

    // Only nurses register new patients
    public function create(User $user): bool
    {
        return $user->isNurse();
    }

    // Only admin/super_admin can edit directly (nurses submit edit requests)
    public function update(User $user, Patient $patient): Response|bool
    {
        if (! $user->isAnyAdmin()) return false;
        if (! $user->isSuperAdmin() && $patient->hospital_id !== $user->hospital_id) {
            return Response::denyWithStatus(404);
        }
        return true;
    }

    // Only admin/super_admin can deactivate patients
    public function delete(User $user, Patient $patient): Response|bool
    {
        if (! $user->isAnyAdmin()) return false;
        if (! $user->isSuperAdmin() && $patient->hospital_id !== $user->hospital_id) {
            return Response::denyWithStatus(404);
        }
        return true;
    }

    // Nurses can enroll; hospital admin can enroll in emergencies
    public function enroll(User $user, Patient $patient): Response|bool
    {
        if (! in_array($user->role, ['nurse', 'admin'], true)) return false;
        if (! $user->isSuperAdmin() && $patient->hospital_id !== $user->hospital_id) {
            return Response::denyWithStatus(404);
        }
        return true;
    }

    // Only admin/super_admin can delete fingerprint records
    public function removeFingerprint(User $user, Patient $patient): Response|bool
    {
        if (! $user->isAnyAdmin()) return false;
        if (! $user->isSuperAdmin() && $patient->hospital_id !== $user->hospital_id) {
            return Response::denyWithStatus(404);
        }
        return true;
    }
}
