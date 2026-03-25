<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // Order matters — users + patients depend on hospitals
        $this->call([
            HospitalSeeder::class,
            UserSeeder::class,
            PatientSeeder::class,
        ]);
    }
}
