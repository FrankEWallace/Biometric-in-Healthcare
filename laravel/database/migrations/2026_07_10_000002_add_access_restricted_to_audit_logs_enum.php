<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Plan 005 introduces the `access_restricted` outcome (identity resolved
 * nationally, but the querying hospital is not authorized for the record).
 * FaceController::verify and VerificationController::verifyHand write an
 * `access_restricted` audit action. Add it to the MySQL enum so the insert
 * is accepted under strict mode.
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
                'user_updated',
                'user_deactivated',
                'hospital_created',
                'hospital_updated',
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
                'stage_override_resolved',
                'access_restricted'
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
                'user_updated',
                'user_deactivated',
                'hospital_created',
                'hospital_updated',
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
};
