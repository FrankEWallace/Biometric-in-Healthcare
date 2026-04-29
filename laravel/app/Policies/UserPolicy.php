<?php

namespace App\Policies;

use App\Models\User;

class UserPolicy
{
    // Admin sees own hospital; super_admin sees all
    public function viewAny(User $user): bool
    {
        return $user->isAnyAdmin();
    }

    // Admin: own hospital or self; super_admin: anyone
    public function view(User $user, User $target): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        if ($user->isAdmin()) {
            return $target->hospital_id === $user->hospital_id;
        }

        // Non-admins can only view themselves
        return $user->id === $target->id;
    }

    // Admin creates users in own hospital; super_admin creates anywhere
    public function create(User $user): bool
    {
        return $user->isAnyAdmin();
    }

    public function update(User $user, User $target): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        if ($user->isAdmin()) {
            return $target->hospital_id === $user->hospital_id;
        }

        // Nurses/doctors can only update themselves
        return $user->id === $target->id;
    }

    // Prevent self-deactivation
    public function delete(User $user, User $target): bool
    {
        if ($user->id === $target->id) {
            return false;
        }

        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isAdmin() && $target->hospital_id === $user->hospital_id;
    }
}
