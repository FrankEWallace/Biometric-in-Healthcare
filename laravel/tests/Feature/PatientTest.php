<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests covering PatientController failure paths.
 *
 * Failure modes exercised:
 *   - Missing required fields on create
 *   - Invalid date format
 *   - NIDA must be exactly 20 chars
 *   - NIDA uniqueness enforcement
 *   - Non-admin attempting soft-delete
 *   - Cross-hospital access (user from hospital A accessing hospital B patient)
 *   - Listing only shows own-hospital patients
 *   - Inactive patients excluded from index
 */
class PatientTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $admin;
    private User $nurse;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create();
        $this->admin    = User::factory()->admin()->create(['hospital_id' => $this->hospital->id]);
        $this->nurse    = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
    }

    // ── Validation failures ───────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_full_name_is_missing(): void
    {
        $this->actingAs($this->nurse)
             ->postJson('/api/patients', ['date_of_birth' => '1990-01-01'])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['full_name']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_date_of_birth_is_missing(): void
    {
        $this->actingAs($this->nurse)
             ->postJson('/api/patients', ['full_name' => 'Test Patient'])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['date_of_birth']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_date_of_birth_format_is_wrong(): void
    {
        $this->actingAs($this->nurse)
             ->postJson('/api/patients', [
                 'full_name'     => 'Test Patient',
                 'date_of_birth' => '01/15/1990',   // expects Y-m-d
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['date_of_birth']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_gender_is_invalid(): void
    {
        $this->actingAs($this->nurse)
             ->postJson('/api/patients', [
                 'full_name'     => 'Test Patient',
                 'date_of_birth' => '1990-01-01',
                 'gender'        => 'unknown',   // not in [male, female, other]
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['gender']);
    }

    // ── NIDA validation ───────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_nida_is_not_exactly_20_chars(): void
    {
        $this->actingAs($this->nurse)
             ->postJson('/api/patients', [
                 'full_name'     => 'Test Patient',
                 'date_of_birth' => '1990-01-01',
                 'nida'          => '1234567',   // too short
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['nida']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function store_fails_when_nida_is_already_taken(): void
    {
        Patient::factory()->create([
            'hospital_id' => $this->hospital->id,
            'nida'        => '12345678901234567890',
        ]);

        $this->actingAs($this->nurse)
             ->postJson('/api/patients', [
                 'full_name'     => 'Another Patient',
                 'date_of_birth' => '1985-06-20',
                 'nida'          => '12345678901234567890',
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['nida']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function update_allows_same_patient_to_keep_their_own_nida(): void
    {
        $patient = Patient::factory()->create([
            'hospital_id' => $this->hospital->id,
            'nida'        => '12345678901234567890',
        ]);

        // Updating with the same NIDA should NOT produce a uniqueness error
        $this->actingAs($this->admin)
             ->putJson("/api/patients/{$patient->id}", [
                 'nida' => '12345678901234567890',
             ])
             ->assertStatus(200);
    }

    // ── Authorization failures ────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function non_admin_cannot_delete_a_patient(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);

        $this->actingAs($this->nurse)
             ->deleteJson("/api/patients/{$patient->id}")
             ->assertStatus(403)
             ->assertJson(['error' => 'Forbidden. Insufficient role.']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function admin_can_soft_delete_own_hospital_patient(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);

        $this->actingAs($this->admin)
             ->deleteJson("/api/patients/{$patient->id}")
             ->assertStatus(200);

        $this->assertDatabaseHas('patients', ['id' => $patient->id, 'is_active' => false]);
    }

    // ── Cross-hospital access ─────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function show_returns_404_for_patient_at_different_hospital(): void
    {
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $this->actingAs($this->nurse)
             ->getJson("/api/patients/{$foreignPatient->id}")
             ->assertStatus(404);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function update_returns_404_for_patient_at_different_hospital(): void
    {
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $this->actingAs($this->admin)
             ->putJson("/api/patients/{$foreignPatient->id}", ['full_name' => 'Hacked'])
             ->assertStatus(404);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function delete_returns_404_for_patient_at_different_hospital(): void
    {
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $this->actingAs($this->admin)
             ->deleteJson("/api/patients/{$foreignPatient->id}")
             ->assertStatus(404);
    }

    // ── Index scoping ─────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function index_excludes_patients_from_other_hospitals(): void
    {
        $ownPatient     = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $response = $this->actingAs($this->nurse)->getJson('/api/patients');

        $response->assertStatus(200);
        $ids = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($ownPatient->id));
        $this->assertFalse($ids->contains($foreignPatient->id));
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function index_excludes_inactive_patients(): void
    {
        $active   = Patient::factory()->create(['hospital_id' => $this->hospital->id, 'is_active' => true]);
        $inactive = Patient::factory()->inactive()->create(['hospital_id' => $this->hospital->id]);

        $response = $this->actingAs($this->nurse)->getJson('/api/patients');
        $ids      = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($active->id));
        $this->assertFalse($ids->contains($inactive->id));
    }
}
