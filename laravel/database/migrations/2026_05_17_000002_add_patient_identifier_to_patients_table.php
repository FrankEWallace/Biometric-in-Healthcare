<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients', function (Blueprint $table) {
            // Auto-incrementing sequence per hospital per year — used to build hospital_patient_id
            $table->unsignedInteger('patient_seq')->nullable()->after('hospital_id');

            // Human-readable unique ID: {HOSPITAL_CODE}-{YEAR}-{NNNNN}
            // Example: BIH-2026-00142
            // Set by the PatientService on registration — not a generated column so it
            // remains readable even if the hospital code changes.
            $table->string('hospital_patient_id', 20)->nullable()->unique()->after('patient_seq');

            $table->index(['hospital_id', 'patient_seq'], 'ix_patients_hospital_seq');
        });
    }

    public function down(): void
    {
        Schema::table('patients', function (Blueprint $table) {
            $table->dropIndex('ix_patients_hospital_seq');
            $table->dropUnique(['hospital_patient_id']);
            $table->dropColumn(['patient_seq', 'hospital_patient_id']);
        });
    }
};
