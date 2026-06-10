<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The face verification flow writes 'needs_review' and 'manually_confirmed'
 * statuses that were never added to the MySQL enum (inserts fail under
 * strict mode), and the new multimodal verify endpoint logs with
 * modality 'multimodal'. Widen both enums.
 *
 * SQLite (tests) is skipped: its CHECK constraints come from the create /
 * add-modality migrations, which now list the full supersets.
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
                'matched', 'no_match', 'error', 'needs_review', 'manually_confirmed'
            ) NOT NULL DEFAULT 'no_match'
        ");

        DB::statement("
            ALTER TABLE verification_logs
            MODIFY COLUMN modality ENUM(
                'fingerprint', 'face', 'multimodal'
            ) NOT NULL DEFAULT 'fingerprint'
        ");
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }

        DB::statement("
            ALTER TABLE verification_logs
            MODIFY COLUMN status ENUM('matched', 'no_match', 'error')
            NOT NULL DEFAULT 'no_match'
        ");

        DB::statement("
            ALTER TABLE verification_logs
            MODIFY COLUMN modality ENUM('fingerprint', 'face')
            NOT NULL DEFAULT 'fingerprint'
        ");
    }
};
