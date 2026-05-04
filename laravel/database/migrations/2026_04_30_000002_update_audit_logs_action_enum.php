<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }
        DB::statement("
            ALTER TABLE audit_logs
            MODIFY COLUMN action ENUM(
                'ehr_access',
                'insurance_check',
                'fingerprint_match',
                'fingerprint_no_match',
                'patient_create',
                'patient_update',
                'patient_delete',
                'fingerprint_enroll',
                'fingerprint_delete',
                'manual_override',
                'fingerprint_lock',
                'fingerprint_unlock',
                'edit_request_submitted',
                'edit_request_approved',
                'edit_request_rejected',
                'edit_request_cancelled',
                'login_success',
                'login_failed',
                'user_created',
                'user_deactivated',
                'hospital_created',
                'hospital_deactivated'
            ) NOT NULL
        ");
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }
        DB::statement("
            ALTER TABLE audit_logs
            MODIFY COLUMN action ENUM(
                'ehr_access',
                'insurance_check',
                'fingerprint_match',
                'patient_create',
                'patient_update',
                'patient_delete',
                'fingerprint_enroll',
                'fingerprint_delete'
            ) NOT NULL
        ");
    }
};
