<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('patients', function (Blueprint $table) {
            $table->id();

            $table->foreignId('hospital_id')
                  ->constrained('hospitals')
                  ->cascadeOnDelete();

            $table->string('full_name', 200);
            $table->date('date_of_birth');
            $table->enum('gender', ['male', 'female', 'other'])->nullable();

            // BiH national identifier — Jedinstveni Matični Broj Građana (13 digits)
            $table->string('jmbg', 13)->nullable()->unique();

            $table->string('phone', 20)->nullable();
            $table->text('notes')->nullable();
            $table->boolean('is_active')->default(true);

            $table->timestamps();

            $table->index('hospital_id');
            $table->index('jmbg');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('patients');
    }
};
