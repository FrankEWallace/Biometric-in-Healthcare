<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The four-finger ("hand slap") verification flow
 * ({@see \App\Http\Controllers\Api\VerificationController::verifyHand}) logs
 * with modality 'hand'. Add it to the enum so inserts don't fail under MySQL
 * strict mode.
 *
 * SQLite (tests) is skipped: its CHECK constraint comes from the create /
 * add-modality migrations, which list the full superset including 'hand'.
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
            MODIFY COLUMN modality ENUM(
                'fingerprint', 'face', 'multimodal', 'hand'
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
            MODIFY COLUMN modality ENUM(
                'fingerprint', 'face', 'multimodal'
            ) NOT NULL DEFAULT 'fingerprint'
        ");
    }
};
