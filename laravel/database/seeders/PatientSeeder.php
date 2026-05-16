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

        $year = now()->year;

        $groups = [
            // ── Sarajevo (BIH) ────────────────────────────────────────
            [
                'hospital'  => $sarajevo,
                'patients'  => [
                    [
                        'full_name'     => 'Amira Kovačević',
                        'date_of_birth' => '1985-07-14',
                        'gender'        => 'female',
                        'nida'          => '1407985175038',
                        'phone'         => '+38761123456',
                        'notes'         => null,
                        'is_active'     => true,
                    ],
                    [
                        'full_name'     => 'Nedim Husić',
                        'date_of_birth' => '1990-03-22',
                        'gender'        => 'male',
                        'nida'          => '2203990175012',
                        'phone'         => '+38762234567',
                        'notes'         => 'Dijabetes tip 2',
                        'is_active'     => true,
                    ],
                    [
                        'full_name'     => 'Fatima Softić',
                        'date_of_birth' => '1975-11-05',
                        'gender'        => 'female',
                        'nida'          => '0511975175021',
                        'phone'         => '+38763345678',
                        'notes'         => null,
                        'is_active'     => true,
                    ],
                    [
                        'full_name'     => 'Kenan Begović',
                        'date_of_birth' => '2000-01-30',
                        'gender'        => 'male',
                        'nida'          => '3001000175099',
                        'phone'         => null,
                        'notes'         => 'Alergija na penicilin',
                        'is_active'     => true,
                    ],
                    // Unenrolled patient — for clerk shortcut demo
                    [
                        'full_name'     => 'Emir Delić',
                        'date_of_birth' => '1998-06-10',
                        'gender'        => 'male',
                        'nida'          => '1006998175077',
                        'phone'         => '+38761999000',
                        'notes'         => 'No fingerprint enrolled yet',
                        'is_active'     => true,
                    ],
                ],
            ],
            // ── Mostar (KBM) ──────────────────────────────────────────
            [
                'hospital'  => $mostar,
                'patients'  => [
                    [
                        'full_name'     => 'Marta Blažević',
                        'date_of_birth' => '1968-09-18',
                        'gender'        => 'female',
                        'nida'          => '1809968178051',
                        'phone'         => '+38763456789',
                        'notes'         => null,
                        'is_active'     => true,
                    ],
                    [
                        'full_name'     => 'Darko Miličević',
                        'date_of_birth' => '1982-04-10',
                        'gender'        => 'male',
                        'nida'          => '1004982178032',
                        'phone'         => '+38761567890',
                        'notes'         => 'Hipertenzija',
                        'is_active'     => true,
                    ],
                    [
                        'full_name'     => 'Anita Jurić',
                        'date_of_birth' => '1995-12-25',
                        'gender'        => 'female',
                        'nida'          => '2512995178044',
                        'phone'         => '+38762678901',
                        'notes'         => null,
                        'is_active'     => true,
                    ],
                ],
            ],
        ];

        foreach ($groups as $group) {
            $hospital = $group['hospital'];
            $code     = strtoupper($hospital->code ?? 'HOS');
            $seq      = 1;

            foreach ($group['patients'] as $data) {
                $data['hospital_id'] = $hospital->id;

                $patient = Patient::firstOrCreate(['nida' => $data['nida']], $data);

                // Assign patient_seq and hospital_patient_id if not yet set
                if (! $patient->hospital_patient_id) {
                    // Find the highest existing seq for this hospital
                    if ($seq === 1) {
                        $max = Patient::where('hospital_id', $hospital->id)
                            ->whereNotNull('patient_seq')
                            ->max('patient_seq');
                        $seq = ($max ?? 0) + 1;
                    }

                    $patient->update([
                        'patient_seq'         => $seq,
                        'hospital_patient_id' => sprintf('%s-%d-%05d', $code, $year, $seq),
                    ]);

                    $seq++;
                }
            }
        }
    }
}
