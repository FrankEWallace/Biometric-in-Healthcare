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
                'name'                    => 'Klinički centar Univerziteta Sarajevo',
                'code'                    => 'BIH',
                'city'                    => 'Sarajevo',
                'wifi_ssid'               => 'KCUS-Staff',
                'gps_latitude'            => 43.8563,
                'gps_longitude'           => 18.4131,
                'gps_radius_meters'       => 300,
                'is_active'               => true,
                'face_recognition_enabled'=> true,
            ],
            [
                'name'                    => 'Klinička bolnica Mostar',
                'code'                    => 'KBM',
                'city'                    => 'Mostar',
                'wifi_ssid'               => 'KBM-Staff',
                'gps_latitude'            => 43.3438,
                'gps_longitude'           => 17.8078,
                'gps_radius_meters'       => 200,
                'is_active'               => true,
                'face_recognition_enabled'=> false,
            ],
            [
                // Demo/presentation hospital — CoICT, University of Dar es Salaam.
                // No wifi_ssid set: geofence check relies on GPS only for the demo.
                'name'                    => 'CoICT Demo Clinic (University of Dar es Salaam)',
                'code'                    => 'COICT',
                'city'                    => 'Dar es Salaam',
                'wifi_ssid'               => null,
                'gps_latitude'            => -6.771349,
                'gps_longitude'           => 39.239748,
                'gps_radius_meters'       => 500,
                'is_active'               => true,
                'face_recognition_enabled'=> true,
            ],
        ];

        foreach ($hospitals as $data) {
            $hospital = Hospital::firstOrCreate(['name' => $data['name']], $data);
            // Ensure code is always up-to-date even on re-seed
            $hospital->update(['code' => $data['code']]);
        }
    }
}
