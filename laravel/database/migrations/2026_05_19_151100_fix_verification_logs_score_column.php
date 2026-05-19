<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            // Score was DECIMAL(5,4) — max 9.9999. Minutiae matching returns 0–100,
            // so widen to DECIMAL(6,2) to accommodate values like 33.75.
            $table->decimal('score', 6, 2)->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            $table->decimal('score', 5, 4)->nullable()->change();
        });
    }
};
