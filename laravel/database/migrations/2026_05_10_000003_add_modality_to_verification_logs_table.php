<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            // Superset kept in sync for SQLite (tests): later ALTERs widen the
            // MySQL enum, but SQLite's CHECK constraint is fixed at create time,
            // so it must list every modality up front ('hand' added 2026-07).
            $table->enum('modality', ['fingerprint', 'face', 'multimodal', 'hand'])
                  ->default('fingerprint')
                  ->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            $table->dropColumn('modality');
        });
    }
};
