<?php

namespace Database\Factories;

use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Crypt;

/**
 * @extends Factory<Fingerprint>
 */
class FingerprintFactory extends Factory
{
    public function definition(): array
    {
        $patient = Patient::factory()->create();

        return [
            'patient_id'      => $patient->id,
            'hospital_id'     => $patient->hospital_id,
            'enrolled_by'     => User::factory()->create(['hospital_id' => $patient->hospital_id])->id,
            'finger_position' => 'right_index',
            'template'        => Crypt::encryptString(json_encode([
                'keypoints'   => [],
                'descriptors' => [],
            ])),
            'quality_score'   => 0.75,
            'is_primary'      => true,
            'is_active'       => true,
        ];
    }

    public function primary(): static
    {
        return $this->state(['is_primary' => true]);
    }

    public function nonPrimary(): static
    {
        return $this->state(['is_primary' => false]);
    }

    public function inactive(): static
    {
        return $this->state(['is_active' => false]);
    }
}
