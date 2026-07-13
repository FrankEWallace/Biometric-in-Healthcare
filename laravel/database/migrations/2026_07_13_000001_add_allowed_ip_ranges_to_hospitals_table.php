<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('hospitals', function (Blueprint $table) {
            $table->text('allowed_ip_ranges')->nullable()->after('wifi_ssid')
                ->comment('Comma-separated CIDR blocks or exact IPs allowed to reach clinical endpoints for this hospital. Null falls back to the private-range defaults in CheckHospitalAccess.');
        });
    }

    public function down(): void
    {
        Schema::table('hospitals', function (Blueprint $table) {
            $table->dropColumn('allowed_ip_ranges');
        });
    }
};
