<?php

namespace App\Services;

use App\Models\Patient;
use App\Models\User;

/**
 * The single access-control seam for patient records.
 *
 * Identity resolution (who is this person?) happens nationally in the biometric
 * engine BEFORE this service is consulted. This service answers the SEPARATE
 * question: may this operator see this identified patient's records at their
 * facility? A cross-hospital hit is never reported as `no_match` — the caller
 * returns `access_restricted` (identity found, records withheld) and audits it.
 *
 * Today the rule is simply "same hospital". Plan 013 grows THIS method
 * (consent tuple, referral grants, break-glass, super-admin) without any change
 * to the biometric controllers — that is why the signature is (User, Patient)
 * rather than (Patient, int $hospitalId).
 */
class PatientAccessService
{
    public function authorizePatientAccess(User $operator, Patient $patient): bool
    {
        return $patient->hospital_id === $operator->hospital_id;
    }
}
