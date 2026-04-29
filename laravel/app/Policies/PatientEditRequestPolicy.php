<?php

namespace App\Policies;

use App\Models\PatientEditRequest;
use App\Models\User;

class PatientEditRequestPolicy
{
    // Nurses submit edit requests; admins shouldn't (they edit directly)
    public function create(User $user): bool
    {
        return $user->isNurse();
    }

    // Nurse can cancel their own pending request
    public function cancel(User $user, PatientEditRequest $editRequest): bool
    {
        return $user->isNurse()
            && $editRequest->requested_by === $user->id
            && $editRequest->status === PatientEditRequest::STATUS_PENDING;
    }

    // Admin/super_admin review requests within their scope
    public function review(User $user, PatientEditRequest $editRequest): bool
    {
        if (! $user->isAnyAdmin()) {
            return false;
        }

        return $user->isSuperAdmin() || $editRequest->hospital_id === $user->hospital_id;
    }

    // Admins see pending requests in their hospital; super_admin sees all
    public function viewAny(User $user): bool
    {
        return $user->isAnyAdmin();
    }
}
