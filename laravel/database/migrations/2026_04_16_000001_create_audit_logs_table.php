<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();

            $table->foreignId('staff_id')
                  ->constrained('users')
                  ->cascadeOnDelete();

            $table->foreignId('patient_id')
                  ->nullable()
                  ->constrained('patients')
                  ->nullOnDelete();

            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            // What was accessed — PDPA 2023 requires logging every access type
            $table->enum('action', [
                'ehr_access',
                'insurance_check',
                'fingerprint_match',
                'patient_create',
                'patient_update',
                'patient_delete',
                'fingerprint_enroll',
                'fingerprint_delete',
            ]);

            // Which GoT-HoMIS module was queried (null for local-only actions)
            $table->string('homis_module', 60)->nullable(); // e.g. patient_registration, insurance

            // Response status from GoT-HoMIS (HTTP status or 'local')
            $table->string('response_status', 10)->nullable();

            // Network context — required for breach traceability
            $table->string('ip_address', 45)->nullable();  // supports IPv6
            $table->string('user_agent', 300)->nullable();

            // Extra structured context (e.g. matched score, eligibility result)
            $table->json('meta')->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->index(['patient_id',  'created_at']);
            $table->index(['staff_id',    'created_at']);
            $table->index(['hospital_id', 'action']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
