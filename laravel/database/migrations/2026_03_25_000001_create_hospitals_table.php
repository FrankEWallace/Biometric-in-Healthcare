<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hospitals', function (Blueprint $table) {
            $table->id();
            $table->string('name', 200);
            $table->string('city', 100);
            $table->string('wifi_ssid', 100)->nullable()->comment('Approved WiFi SSID for geofencing');
            $table->decimal('gps_latitude', 10, 7)->nullable();
            $table->decimal('gps_longitude', 10, 7)->nullable();
            $table->unsignedSmallInteger('gps_radius_meters')->default(200)->comment('Allowed radius around GPS centre');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hospitals');
    }
};
