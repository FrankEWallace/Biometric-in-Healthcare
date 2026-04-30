<?php

namespace App\Policies;

use App\Models\Fingerprint;
use App\Models\User;

class FingerprintPolicy
{
    // Only admin/super_admin can unlock locked fingerprint records
    public function unlock(User $user, Fingerprint $fingerprint): bool
    {
        if (! $user->isAnyAdmin()) {
            return false;
        }

        return $user->isSuperAdmin() || $fingerprint->hospital_id === $user->hospital_id;
    }

    // Only admin/super_admin can delete fingerprint records
    public function delete(User $user, Fingerprint $fingerprint): bool
    {
        if (! $user->isAnyAdmin()) {
            return false;
        }

        return $user->isSuperAdmin() || $fingerprint->hospital_id === $user->hospital_id;
    }
}
