<?php

namespace Database\Factories;

use App\Models\Hospital;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Hospital>
 */
class HospitalFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name'              => fake()->company() . ' Hospital',
            'city'              => fake()->city(),
            'wifi_ssid'         => null,
            'gps_latitude'      => null,
            'gps_longitude'     => null,
            'gps_radius_meters' => 200,
            'is_active'         => true,
        ];
    }

    /** Hospital with GPS geofencing configured (Sarajevo centre). */
    public function withGps(float $lat = 43.8563, float $lon = 18.4131, int $radius = 300): static
    {
        return $this->state([
            'gps_latitude'      => $lat,
            'gps_longitude'     => $lon,
            'gps_radius_meters' => $radius,
        ]);
    }

    /** Hospital with WiFi SSID restriction configured. */
    public function withWifi(string $ssid = 'HOSPITAL-STAFF'): static
    {
        return $this->state(['wifi_ssid' => $ssid]);
    }

    /** Hospital with both GPS and WiFi configured. */
    public function withGeofence(): static
    {
        return $this->withGps()->withWifi();
    }
}
