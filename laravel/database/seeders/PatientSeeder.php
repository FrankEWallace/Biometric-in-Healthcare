<?php

namespace Database\Seeders;

use App\Models\Hospital;
use App\Models\Patient;
use Illuminate\Database\Seeder;

class PatientSeeder extends Seeder
{
    public function run(): void
    {
        $sarajevo = Hospital::where('city', 'Sarajevo')->first();
        $mostar   = Hospital::where('city', 'Mostar')->first();

        $patients = [
            // ── Sarajevo ──────────────────────────────────────────────
            [
                'hospital_id'   => $sarajevo->id,
                'full_name'     => 'Amira Kovačević',
                'date_of_birth' => '1985-07-14',
                'gender'        => 'female',
                'jmbg'          => '1407985175038',
                'phone'         => '+38761123456',
                'notes'         => null,
                'is_active'     => true,
            ],
            [
                'hospital_id'   => $sarajevo->id,
                'full_name'     => 'Nedim Husić',
                'date_of_birth' => '1990-03-22',
                'gender'        => 'male',
                'jmbg'          => '2203990175012',
                'phone'         => '+38762234567',
                'notes'         => 'Dijabetes tip 2',
                'is_active'     => true,
            ],
            [
                'hospital_id'   => $sarajevo->id,
                'full_name'     => 'Fatima Softić',
                'date_of_birth' => '1975-11-05',
                'gender'        => 'female',
                'jmbg'          => '0511975175021',
                'phone'         => '+38763345678',
                'notes'         => null,
                'is_active'     => true,
            ],
            [
                'hospital_id'   => $sarajevo->id,
                'full_name'     => 'Kenan Begović',
                'date_of_birth' => '2000-01-30',
                'gender'        => 'male',
                'jmbg'          => '3001000175099',
                'phone'         => null,
                'notes'         => 'Alergija na penicilin',
                'is_active'     => true,
            ],

            // ── Mostar ────────────────────────────────────────────────
            [
                'hospital_id'   => $mostar->id,
                'full_name'     => 'Marta Blažević',
                'date_of_birth' => '1968-09-18',
                'gender'        => 'female',
                'jmbg'          => '1809968178051',
                'phone'         => '+38763456789',
                'notes'         => null,
                'is_active'     => true,
            ],
            [
                'hospital_id'   => $mostar->id,
                'full_name'     => 'Darko Miličević',
                'date_of_birth' => '1982-04-10',
                'gender'        => 'male',
                'jmbg'          => '1004982178032',
                'phone'         => '+38761567890',
                'notes'         => 'Hipertenzija',
                'is_active'     => true,
            ],
            [
                'hospital_id'   => $mostar->id,
                'full_name'     => 'Anita Jurić',
                'date_of_birth' => '1995-12-25',
                'gender'        => 'female',
                'jmbg'          => '2512995178044',
                'phone'         => '+38762678901',
                'notes'         => null,
                'is_active'     => true,
            ],
        ];

        foreach ($patients as $data) {
            Patient::firstOrCreate(['jmbg' => $data['jmbg']], $data);
        }
    }
}
