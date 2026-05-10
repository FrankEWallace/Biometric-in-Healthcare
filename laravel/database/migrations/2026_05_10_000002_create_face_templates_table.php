<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('face_templates', function (Blueprint $table) {
            $table->id();

            $table->foreignId('patient_id')
                  ->constrained('patients')
                  ->cascadeOnDelete();

            // Denormalised from patients — avoids JOIN on every hospital-wide scan.
            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            $table->foreignId('enrolled_by')
                  ->constrained('users');

            // AES-256-CBC encrypted JSON: { "embedding": [...float] }
            // Raw embedding is NEVER written to disk unencrypted.
            $table->longText('template')
                  ->comment('Encrypted face embedding vector JSON from Python service');

            // Image clarity score [0.000–1.000] returned by Python /face/process.
            $table->decimal('quality_score', 4, 3)->nullable();

            $table->boolean('is_active')->default(true);

            $table->timestamps();

            // One face template per patient (re-enrollment replaces the existing row)
            $table->unique('patient_id', 'uq_face_patient');

            // Fast path: all active face templates for a hospital
            $table->index(['hospital_id', 'is_active'], 'ix_ft_hospital_active');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('face_templates');
    }
};
