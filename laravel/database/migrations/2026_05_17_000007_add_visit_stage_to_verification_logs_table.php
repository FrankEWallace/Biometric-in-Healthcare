<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            // Nullable — standalone verifications (enrollment checks, etc.) have no visit stage
            $table->foreignId('visit_stage_id')
                  ->nullable()
                  ->after('hospital_id')
                  ->constrained('visit_stages')
                  ->nullOnDelete();

            $table->index('visit_stage_id');
        });
    }

    public function down(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            $table->dropForeign(['visit_stage_id']);
            $table->dropIndex(['visit_stage_id']);
            $table->dropColumn('visit_stage_id');
        });
    }
};
