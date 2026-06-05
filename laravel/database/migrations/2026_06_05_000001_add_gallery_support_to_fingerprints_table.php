<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Multi-capture ("gallery of 3") fingerprint enrollment support.
 *
 * Each finger may now store up to 3 templates (different angles / ridge
 * coverage), matched with the Max-Rule at 1:1 verification time. To keep 1:N
 * identification one-template-per-finger (avoiding FAR inflation and 3x latency),
 * exactly one template per (patient, finger_position) is flagged is_gallery_lead.
 *
 * Decisions: see .claude/grill-sessions/2026-06-05-multi-capture-fingerprint-enrollment.md
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fingerprints', function (Blueprint $table) {
            // The single 1:N representative for this (patient, finger_position).
            // Defaults true so every existing single-template row becomes its own
            // lead and keeps working unchanged after this migration.
            if (! Schema::hasColumn('fingerprints', 'is_gallery_lead')) {
                $table->boolean('is_gallery_lead')->default(true)->after('is_primary');
            }

            // Set when a finger enrolled with degraded coverage (< 3 usable
            // captures). Flags the patient for re-enrollment when conditions allow.
            if (! Schema::hasColumn('fingerprints', 'needs_reenrollment')) {
                $table->boolean('needs_reenrollment')->default(false)->after('is_gallery_lead');
            }
        });

        // The unique uq_patient_finger(patient_id, finger_position) is the only
        // index leading with patient_id, so on MySQL it serves the patient_id
        // foreign key and cannot be dropped directly (errno 1553). Add a
        // non-unique index on the same columns first to keep the FK covered and
        // preserve (patient_id, finger_position) lookups.
        Schema::table('fingerprints', function (Blueprint $table) {
            $table->index(['patient_id', 'finger_position'], 'ix_fp_patient_finger');
        });

        Schema::table('fingerprints', function (Blueprint $table) {
            // A finger may now have multiple templates — drop the 1-per-finger rule.
            $table->dropUnique('uq_patient_finger');

            // 1:N scans filter is_gallery_lead = true (both primary and fallback
            // passes) so identification stays one-template-per-finger.
            $table->index(
                ['hospital_id', 'is_gallery_lead', 'is_active'],
                'ix_fp_hospital_lead_active'
            );
        });
    }

    public function down(): void
    {
        Schema::table('fingerprints', function (Blueprint $table) {
            $table->dropIndex('ix_fp_hospital_lead_active');
            $table->unique(['patient_id', 'finger_position'], 'uq_patient_finger');
            $table->dropIndex('ix_fp_patient_finger');
            $table->dropColumn(['is_gallery_lead', 'needs_reenrollment']);
        });
    }
};
