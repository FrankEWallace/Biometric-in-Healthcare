<?php

namespace Database\Factories;

use App\Models\Hospital;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    protected static ?string $password;

    public function definition(): array
    {
        return [
            'hospital_id' => Hospital::inRandomOrder()->value('id') ?? 1,
            'name'        => fake()->name(),
            'username'    => fake()->unique()->userName(),
            'email'       => fake()->unique()->safeEmail(),
            'password'    => static::$password ??= Hash::make('password'),
            'role'        => fake()->randomElement(['admin', 'nurse', 'doctor']),
            'is_active'   => true,
            'remember_token' => Str::random(10),
        ];
    }

    public function admin(): static
    {
        return $this->state(fn () => ['role' => 'admin']);
    }

    public function nurse(): static
    {
        return $this->state(fn () => ['role' => 'nurse']);
    }

    public function doctor(): static
    {
        return $this->state(fn () => ['role' => 'doctor']);
    }

    public function inactive(): static
    {
        return $this->state(fn () => ['is_active' => false]);
    }
}
