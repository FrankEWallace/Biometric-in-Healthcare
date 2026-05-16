<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // Order matters — each seeder depends on the ones before it
        $this->call([
            HospitalSeeder::class,
            UserSeeder::class,
            PatientSeeder::class,
            VisitSeeder::class,
        ]);
    }
}
