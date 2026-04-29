<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('patient_edit_requests', function (Blueprint $table) {
            $table->id();

            $table->foreignId('patient_id')
                  ->constrained('patients')
                  ->cascadeOnDelete();

            $table->foreignId('requested_by')
                  ->constrained('users')
                  ->cascadeOnDelete();

            $table->foreignId('reviewed_by')
                  ->nullable()
                  ->constrained('users')
                  ->nullOnDelete();

            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            // e.g. 'full_name', 'phone', 'date_of_birth', 'gender', 'jmbg'
            $table->string('field_name', 60);

            $table->text('old_value');
            $table->text('new_value');

            // Required — nurse must justify every identity change
            $table->string('reason', 500);

            $table->enum('status', ['pending', 'approved', 'rejected', 'cancelled'])
                  ->default('pending');

            $table->timestamp('reviewed_at')->nullable();

            // Auto-reject 30 days after submission
            $table->timestamp('expires_at');

            $table->timestamp('created_at')->useCurrent();

            $table->index(['patient_id', 'status']);
            $table->index(['hospital_id', 'status']);
            $table->index('expires_at'); // for scheduled expiry job
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('patient_edit_requests');
    }
};
