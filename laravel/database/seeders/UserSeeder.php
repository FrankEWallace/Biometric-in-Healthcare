<?php

namespace Database\Seeders;

use App\Models\Hospital;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class UserSeeder extends Seeder
{
    public function run(): void
    {
        $sarajevo = Hospital::where('city', 'Sarajevo')->first();
        $mostar   = Hospital::where('city', 'Mostar')->first();

        $users = [
            // ── Sarajevo ──────────────────────────────────────────────
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Amir Hadžić',
                'username'    => 'admin.sarajevo',
                'email'       => 'admin@kcus.ba',
                'password'    => Hash::make('Admin@1234'),
                'role'        => 'admin',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Emina Karić',
                'username'    => 'nurse.emina',
                'email'       => 'emina.karic@kcus.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Selma Begić',
                'username'    => 'nurse.selma',
                'email'       => 'selma.begic@kcus.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Dr. Tarik Mujanović',
                'username'    => 'dr.tarik',
                'email'       => 'tarik.mujanovic@kcus.ba',
                'password'    => Hash::make('Doctor@1234'),
                'role'        => 'doctor',
                'is_active'   => true,
            ],

            // ── Mostar ────────────────────────────────────────────────
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Jasna Zelenika',
                'username'    => 'admin.mostar',
                'email'       => 'admin@kbm.ba',
                'password'    => Hash::make('Admin@1234'),
                'role'        => 'admin',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Mirela Ćosić',
                'username'    => 'nurse.mirela',
                'email'       => 'mirela.cosic@kbm.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Dr. Ivan Perić',
                'username'    => 'dr.ivan',
                'email'       => 'ivan.peric@kbm.ba',
                'password'    => Hash::make('Doctor@1234'),
                'role'        => 'doctor',
                'is_active'   => true,
            ],
        ];

        foreach ($users as $data) {
            User::firstOrCreate(['username' => $data['username']], $data);
        }
    }
}
