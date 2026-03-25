<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fingerprints', function (Blueprint $table) {
            $table->id();

            $table->foreignId('patient_id')
                  ->constrained('patients')
                  ->cascadeOnDelete();

            // Denormalised from patients for direct hospital-scoped queries —
            // avoids a JOIN on every 1-to-N matching scan.
            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            $table->foreignId('enrolled_by')
                  ->constrained('users');

            $table->enum('finger_position', [
                'right_thumb',  'right_index',  'right_middle',  'right_ring',  'right_little',
                'left_thumb',   'left_index',   'left_middle',   'left_ring',   'left_little',
            ])->default('right_index');

            // AES-256-CBC encrypted JSON: { "keypoints": [...], "descriptors": [[...]] }
            // Encrypted by Laravel Crypt::encryptString() before storage.
            // Raw template is NEVER written to disk unencrypted.
            $table->longText('template')
                  ->comment('Encrypted ORB template JSON from Python service');

            // Quality score [0.000–1.000] returned by Python /process.
            // Enrollments below MIN_QUALITY_SCORE (0.30) are rejected at the API layer.
            $table->decimal('quality_score', 4, 3)->nullable();

            $table->boolean('is_primary')->default(false);
            $table->boolean('is_active')->default(true);

            $table->timestamps();

            // --- Constraints ---

            // One template per finger per patient
            $table->unique(['patient_id', 'finger_position'], 'uq_patient_finger');

            // --- Indexes ---

            // Fast path: fetch only primary, active fingerprints for a given hospital
            // (used in pass-1 of two-pass matching)
            $table->index(['hospital_id', 'is_primary', 'is_active'], 'ix_fp_hospital_primary_active');

            // Fallback path: all active fingerprints for a hospital (pass-2)
            $table->index(['hospital_id', 'is_active'], 'ix_fp_hospital_active');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fingerprints');
    }
};
