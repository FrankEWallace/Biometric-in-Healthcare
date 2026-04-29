<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fingerprints', function (Blueprint $table) {
            // Counts consecutive failed verifications within the 1-hour window.
            // Resets to 0 on a successful match or admin unlock.
            $table->unsignedTinyInteger('failed_attempts')->default(0)->after('is_active');

            // Set when failed_attempts reaches 3 within 1 hour.
            // NULL means the record is not locked.
            $table->timestamp('locked_at')->nullable()->after('failed_attempts');

            // Tracks when the lock window started for the 1-hour rolling check.
            $table->timestamp('attempts_window_start')->nullable()->after('locked_at');

            $table->index('locked_at'); // fast check: fetch all locked records
        });
    }

    public function down(): void
    {
        Schema::table('fingerprints', function (Blueprint $table) {
            $table->dropIndex(['locked_at']);
            $table->dropColumn(['failed_attempts', 'locked_at', 'attempts_window_start']);
        });
    }
};
