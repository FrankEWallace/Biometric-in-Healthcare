<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * FaceController::confirmReview has been writing 'face_manual_confirm'
 * audit rows, but the action was never added to the MySQL enum — the
 * insert fails under strict mode. Add it.
 *
 * SQLite (tests) is skipped: its CHECK constraint comes from the
 * create_audit_logs_table migration, which now lists the full superset.
 */
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
                'hospital_deactivated',
                'face_enroll',
                'face_match',
                'face_no_match',
                'face_manual_confirm',
                'visit_open',
                'visit_close',
                'visit_reopen',
                'stage_verified',
                'stage_override_requested',
                'stage_override_resolved'
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
                'hospital_deactivated',
                'face_enroll',
                'face_match',
                'face_no_match',
                'visit_open',
                'visit_close',
                'visit_reopen',
                'stage_verified',
                'stage_override_requested',
                'stage_override_resolved'
            ) NOT NULL
        ");
    }
};
