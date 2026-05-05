<?php

namespace Database\Factories;

use App\Models\Hospital;
use App\Models\Patient;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Patient>
 */
class PatientFactory extends Factory
{
    public function definition(): array
    {
        return [
            'hospital_id'   => Hospital::factory(),
            'full_name'     => fake()->name(),
            'date_of_birth' => fake()->date('Y-m-d', '-18 years'),
            'gender'        => fake()->randomElement(['male', 'female', 'other']),
            'nida'          => null,
            'phone'         => null,
            'notes'         => null,
            'is_active'     => true,
        ];
    }

    public function withJmbg(string $nida = '12345678901234567890'): static
    {
        return $this->state(['nida' => $nida]);
    }

    public function inactive(): static
    {
        return $this->state(['is_active' => false]);
    }
}
