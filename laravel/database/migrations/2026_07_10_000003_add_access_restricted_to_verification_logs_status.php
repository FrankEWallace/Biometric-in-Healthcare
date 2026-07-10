<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Plan 005: a cross-hospital biometric hit is logged with status
 * `access_restricted` (identity resolved, records withheld) instead of a
 * fake `no_match`. Add it to the MySQL status enum.
 *
 * SQLite (tests) is skipped: its CHECK constraint comes from the
 * create_verification_logs_table migration, which now lists the full superset.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }

        DB::statement("
            ALTER TABLE verification_logs
            MODIFY COLUMN status ENUM(
                'matched', 'no_match', 'error', 'needs_review', 'manually_confirmed',
                'access_restricted'
            ) NOT NULL DEFAULT 'no_match'
        ");
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }

        DB::statement("
            ALTER TABLE verification_logs
            MODIFY COLUMN status ENUM(
                'matched', 'no_match', 'error', 'needs_review', 'manually_confirmed'
            ) NOT NULL DEFAULT 'no_match'
        ");
    }
};
