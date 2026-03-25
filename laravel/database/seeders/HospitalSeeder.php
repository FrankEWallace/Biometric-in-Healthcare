<?php

namespace Database\Seeders;

use App\Models\Hospital;
use Illuminate\Database\Seeder;

class HospitalSeeder extends Seeder
{
    public function run(): void
    {
        $hospitals = [
            [
                'name'              => 'Klinički centar Univerziteta Sarajevo',
                'city'              => 'Sarajevo',
                'wifi_ssid'         => 'KCUS-Staff',
                'gps_latitude'      => 43.8563,
                'gps_longitude'     => 18.4131,
                'gps_radius_meters' => 300,
                'is_active'         => true,
            ],
            [
                'name'              => 'Klinička bolnica Mostar',
                'city'              => 'Mostar',
                'wifi_ssid'         => 'KBM-Staff',
                'gps_latitude'      => 43.3438,
                'gps_longitude'     => 17.8078,
                'gps_radius_meters' => 200,
                'is_active'         => true,
            ],
        ];

        foreach ($hospitals as $data) {
            Hospital::firstOrCreate(['name' => $data['name']], $data);
        }
    }
}
