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
            // ── Super Admin (no hospital scope) ───────────────────────
            [
                'hospital_id' => $sarajevo->id, // placeholder — super admin ignores hospital scope
                'name'        => 'System Administrator',
                'username'    => 'superadmin',
                'email'       => 'superadmin@bih.system',
                'password'    => Hash::make('SuperAdmin@1234'),
                'role'        => 'super_admin',
                'is_active'   => true,
            ],

            // ── Sarajevo ──────────────────────────────────────────────
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'George Ray',
                'username'    => 'george.ray',
                'email'       => 'george.ray@kcus.ba',
                'password'    => Hash::make('Admin@1234'),
                'role'        => 'admin',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Editha Deo',
                'username'    => 'editha.deo',
                'email'       => 'editha.deo@kcus.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Juma Shabani',
                'username'    => 'juma.shabani',
                'email'       => 'juma.shabani@kcus.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $sarajevo->id,
                'name'        => 'Dr. Joseph Mushi',
                'username'    => 'dr.joseph',
                'email'       => 'joseph.mushi@kcus.ba',
                'password'    => Hash::make('Doctor@1234'),
                'role'        => 'doctor',
                'is_active'   => true,
            ],

            // ── Mostar ────────────────────────────────────────────────
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Ivan Bariki',
                'username'    => 'ivan.bariki',
                'email'       => 'ivan.bariki@kbm.ba',
                'password'    => Hash::make('Admin@1234'),
                'role'        => 'admin',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Ben Mazi',
                'username'    => 'ben.mazi',
                'email'       => 'ben.mazi@kbm.ba',
                'password'    => Hash::make('Nurse@1234'),
                'role'        => 'nurse',
                'is_active'   => true,
            ],
            [
                'hospital_id' => $mostar->id,
                'name'        => 'Dr. Edward Kimaro',
                'username'    => 'dr.edward',
                'email'       => 'edward.kimaro@kbm.ba',
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
