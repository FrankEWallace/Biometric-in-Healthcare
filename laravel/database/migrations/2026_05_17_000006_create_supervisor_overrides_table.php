<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('supervisor_overrides', function (Blueprint $table) {
            $table->id();

            // The stage at which biometric verification failed
            $table->foreignId('visit_stage_id')
                  ->constrained('visit_stages')
                  ->cascadeOnDelete();

            // Staff member at the station who triggered the override request
            $table->foreignId('requested_by')
                  ->constrained('users');

            // Supervisor who approved or denied — null until resolved
            $table->foreignId('supervisor_id')
                  ->nullable()
                  ->constrained('users')
                  ->nullOnDelete();

            $table->enum('status', ['pending', 'approved', 'denied'])->default('pending');

            // Which biometric methods were attempted before escalating
            $table->enum('fallback_chain', [
                'fingerprint_failed',
                'fingerprint_and_face_failed',
            ])->default('fingerprint_and_face_failed');

            // Optional note from the requesting staff member
            $table->string('staff_note', 255)->nullable();

            // Optional note from the supervisor when resolving
            $table->string('supervisor_note', 255)->nullable();

            $table->timestamp('requested_at')->useCurrent();
            $table->timestamp('resolved_at')->nullable();

            $table->timestamps();

            $table->index(['visit_stage_id', 'status'], 'ix_overrides_stage_status');
            $table->index('status');
            $table->index('requested_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('supervisor_overrides');
    }
};
