<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            $table->enum('modality', ['fingerprint', 'face', 'multimodal'])
                  ->default('fingerprint')
                  ->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('verification_logs', function (Blueprint $table) {
            $table->dropColumn('modality');
        });
    }
};
