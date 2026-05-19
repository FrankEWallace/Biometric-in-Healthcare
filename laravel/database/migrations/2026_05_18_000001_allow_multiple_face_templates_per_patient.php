<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Allow multiple face templates per patient (multi-sample enrollment).
 *
 * Previously the table enforced one template per patient via uq_face_patient.
 * The new design stores up to MAX_TEMPLATES_PER_PATIENT active templates,
 * giving the FAISS matcher several enrollment samples to search against and
 * improving recall under varying lighting and angle conditions.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Add the replacement index first — MySQL requires the FK on patient_id
        // to always have a backing index.  The composite index satisfies that
        // requirement once it exists, allowing the unique one to be dropped.
        Schema::table('face_templates', function (Blueprint $table) {
            $table->index(['patient_id', 'is_active'], 'ix_ft_patient_active');
        });

        Schema::table('face_templates', function (Blueprint $table) {
            $table->dropUnique('uq_face_patient');
        });
    }

    public function down(): void
    {
        Schema::table('face_templates', function (Blueprint $table) {
            $table->unique('patient_id', 'uq_face_patient');
        });

        Schema::table('face_templates', function (Blueprint $table) {
            $table->dropIndex('ix_ft_patient_active');
        });
    }
};
