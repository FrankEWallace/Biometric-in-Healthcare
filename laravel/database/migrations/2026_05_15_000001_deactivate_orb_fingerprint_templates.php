<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ORB → SourceAFIS migration.
 *
 * All previously enrolled fingerprints used ORB feature descriptors.
 * SourceAFIS uses a completely different minutiae representation — the
 * two formats are binary-incompatible and cannot be matched across systems.
 *
 * This migration:
 *   1. Adds a `template_format` column so callers can detect which algorithm
 *      produced each stored template.
 *   2. Marks every existing record as ORB-format and deactivates it so the
 *      new matcher never attempts to load an incompatible blob.
 *
 * Patients must be re-enrolled after this migration runs.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fingerprints', function (Blueprint $table) {
            $table->string('template_format', 32)
                  ->default('orb_v1')
                  ->after('template')
                  ->comment('Algorithm that produced the stored template: orb_v1 | sourceafis_v1');
        });

        // Deactivate all existing ORB records — incompatible with SourceAFIS matcher
        DB::table('fingerprints')->update([
            'is_active'       => false,
            'template_format' => 'orb_v1',
        ]);
    }

    public function down(): void
    {
        // Reactivating ORB records on rollback would restore incompatible templates;
        // leave them deactivated so a rollback doesn't silently break matching.
        Schema::table('fingerprints', function (Blueprint $table) {
            $table->dropColumn('template_format');
        });
    }
};
