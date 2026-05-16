<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('visit_stages', function (Blueprint $table) {
            $table->id();

            $table->foreignId('visit_id')
                  ->constrained('visits')
                  ->cascadeOnDelete();

            $table->enum('stage', [
                'clerk_checkin',
                'triage',
                'consultation',
                'laboratory',
                'pharmacy',
                'clerk_checkout',
            ]);

            $table->enum('status', ['pending', 'completed'])->default('pending');

            // Staff member who performed the verification at this stage
            $table->foreignId('verified_by')
                  ->nullable()
                  ->constrained('users')
                  ->nullOnDelete();

            // The biometric event that confirmed identity at this stage
            $table->foreignId('verification_log_id')
                  ->nullable()
                  ->constrained('verification_logs')
                  ->nullOnDelete();

            $table->timestamp('verified_at')->nullable();

            // Stage-specific simulated EMR data (JSON)
            // triage:       { bp, pulse, temp, weight, visit_type_set }
            // consultation: { diagnosis, notes, lab_orders[], prescriptions[] }
            // laboratory:   { tests[{ name, result, value }] }
            // pharmacy:     { medications[{ name, dosage, dispensed }] }
            $table->json('simulated_data')->nullable();

            $table->timestamps();

            // A visit can only have one record per stage
            $table->unique(['visit_id', 'stage'], 'uq_visit_stage');

            $table->index(['visit_id', 'status'], 'ix_visit_stages_visit_status');
            $table->index('stage');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('visit_stages');
    }
};
