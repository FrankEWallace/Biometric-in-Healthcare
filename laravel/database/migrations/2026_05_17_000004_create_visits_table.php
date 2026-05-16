<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('visits', function (Blueprint $table) {
            $table->id();

            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            $table->foreignId('patient_id')
                  ->constrained('patients')
                  ->cascadeOnDelete();

            $table->foreignId('opened_by')
                  ->constrained('users');

            $table->foreignId('closed_by')
                  ->nullable()
                  ->constrained('users')
                  ->nullOnDelete();

            // Set by Triage nurse after clinical assessment
            $table->enum('visit_type', ['pending', 'opd', 'ipd'])->default('pending');

            $table->enum('status', ['open', 'closed'])->default('open');

            $table->timestamp('opened_at')->useCurrent();
            $table->timestamp('closed_at')->nullable();

            // Tracks same-day reopens — each reopen increments this
            $table->unsignedTinyInteger('reopen_count')->default(0);

            // Required when reopening: reason logged for audit
            $table->string('reopen_reason', 255)->nullable();

            $table->index(['hospital_id', 'status'], 'ix_visits_hospital_status');
            $table->index(['patient_id', 'status'], 'ix_visits_patient_status');
            $table->index('opened_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('visits');
    }
};
