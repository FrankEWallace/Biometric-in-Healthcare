<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('verification_logs', function (Blueprint $table) {
            $table->id();

            // Nullable — NULL means no patient was identified
            $table->foreignId('patient_id')
                  ->nullable()
                  ->constrained('patients')
                  ->nullOnDelete();

            // Which specific fingerprint record was matched (nullable — no match)
            $table->foreignId('fingerprint_id')
                  ->nullable()
                  ->constrained('fingerprints')
                  ->nullOnDelete();

            $table->foreignId('operator_id')
                  ->constrained('users')
                  ->cascadeOnDelete();

            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            // Match score [0.0000–1.0000] from Python /match
            $table->decimal('score', 5, 4)->nullable();

            $table->enum('status', ['matched', 'no_match', 'error'])
                  ->default('no_match');

            // Device location at time of verification
            $table->decimal('gps_latitude',  10, 7)->nullable();
            $table->decimal('gps_longitude', 10, 7)->nullable();
            $table->string('wifi_ssid', 100)->nullable();

            $table->text('error_message')->nullable();

            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrentOnUpdate()->nullable();

            $table->index('patient_id');
            $table->index('operator_id');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('verification_logs');
    }
};
