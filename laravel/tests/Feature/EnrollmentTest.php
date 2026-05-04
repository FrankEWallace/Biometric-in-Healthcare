<?php

namespace Tests\Feature;

use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FingerprintService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * Tests covering fingerprint enrollment failure paths (POST /api/patients/{id}/enroll).
 *
 * Failure modes exercised:
 *   - Invalid finger_position value
 *   - Quality score below the 0.30 minimum threshold
 *   - Python microservice unavailable (RuntimeException)
 *   - Cross-hospital enrollment attempt
 *   - Re-enrolling same finger upserts rather than creating a duplicate
 *   - Marking a second fingerprint as primary demotes the previous one
 */
class EnrollmentTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $nurse;
    private User $admin;
    private Patient $patient;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create();
        $this->nurse    = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
        $this->admin    = User::factory()->admin()->create(['hospital_id' => $this->hospital->id]);
        $this->patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
    }

    // ── Field validation ──────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_fails_when_image_is_missing(): void
    {
        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$this->patient->id}/enroll", [])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['image']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_fails_with_invalid_finger_position(): void
    {
        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$this->patient->id}/enroll", [
                 'image'           => base64_encode('fake-image-data'),
                 'finger_position' => 'left_ear',   // not a valid position
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['finger_position']);
    }

    // ── Quality gate ──────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_rejects_fingerprint_when_quality_score_is_below_threshold(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.15,   // below MIN_QUALITY_SCORE = 0.30
            ]);
        });

        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$this->patient->id}/enroll", [
                 'image' => base64_encode('blurry-image'),
             ])
             ->assertStatus(422)
             ->assertJsonPath('error', 'Fingerprint quality is too low. Please recapture.')
             ->assertJsonPath('minimum', 0.30);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_accepts_fingerprint_at_exact_quality_threshold(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.30,   // exactly at threshold — must pass
            ]);
        });

        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$this->patient->id}/enroll", [
                 'image' => base64_encode('borderline-image'),
             ])
             ->assertStatus(201);
    }

    // ── Python service failure ────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_returns_500_when_python_service_is_down(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')
                 ->once()
                 ->andThrow(new RuntimeException('Connection refused'));
        });

        // Laravel's validation exception is thrown before service call only if
        // 'image' is present — ensure we hit the service layer
        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$this->patient->id}/enroll", [
                 'image' => base64_encode('some-image-data'),
             ])
             ->assertStatus(500);
    }

    // ── Cross-hospital ────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function enroll_returns_404_for_patient_at_different_hospital(): void
    {
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $this->actingAs($this->nurse)
             ->postJson("/api/patients/{$foreignPatient->id}/enroll", [
                 'image' => base64_encode('fake-image'),
             ])
             ->assertStatus(404);
    }

    // ── Upsert behaviour ──────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function re_enrolling_same_finger_overwrites_old_template_not_duplicate(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->twice()->andReturn([
                'template'      => ['keypoints' => [1], 'descriptors' => [2]],
                'quality_score' => 0.80,
            ]);
        });

        $payload = ['image' => base64_encode('img'), 'finger_position' => 'right_index'];

        $this->actingAs($this->nurse)->postJson("/api/patients/{$this->patient->id}/enroll", $payload)->assertStatus(201);
        $this->actingAs($this->nurse)->postJson("/api/patients/{$this->patient->id}/enroll", $payload)->assertStatus(201);

        // Must still be exactly one fingerprint row for right_index
        $this->assertDatabaseCount('fingerprints', 1);
    }

    // ── Primary flag management ───────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function marking_second_fingerprint_as_primary_demotes_the_first(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->twice()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
        });

        // Enroll right_index as primary
        $this->actingAs($this->nurse)->postJson("/api/patients/{$this->patient->id}/enroll", [
            'image'           => base64_encode('img1'),
            'finger_position' => 'right_index',
            'is_primary'      => true,
        ])->assertStatus(201);

        // Enroll left_index and mark it as the new primary
        $this->actingAs($this->nurse)->postJson("/api/patients/{$this->patient->id}/enroll", [
            'image'           => base64_encode('img2'),
            'finger_position' => 'left_index',
            'is_primary'      => true,
        ])->assertStatus(201);

        // right_index must have been demoted
        $this->assertDatabaseHas('fingerprints', [
            'patient_id'      => $this->patient->id,
            'finger_position' => 'right_index',
            'is_primary'      => false,
        ]);

        // left_index must now be primary
        $this->assertDatabaseHas('fingerprints', [
            'patient_id'      => $this->patient->id,
            'finger_position' => 'left_index',
            'is_primary'      => true,
        ]);
    }

    // ── Remove fingerprint ────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function remove_fingerprint_soft_deletes_only_own_hospitals_record(): void
    {
        $fp = Fingerprint::factory()->create([
            'patient_id'  => $this->patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->nurse->id,
        ]);

        $this->actingAs($this->admin)
             ->deleteJson("/api/patients/{$this->patient->id}/fingerprints/{$fp->id}")
             ->assertStatus(200);

        $this->assertDatabaseHas('fingerprints', ['id' => $fp->id, 'is_active' => false]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function remove_fingerprint_returns_404_when_fingerprint_belongs_to_other_patient(): void
    {
        $otherPatient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $fp           = Fingerprint::factory()->create([
            'patient_id'  => $otherPatient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->nurse->id,
        ]);

        // Mismatched patient/fingerprint combination
        $this->actingAs($this->admin)
             ->deleteJson("/api/patients/{$this->patient->id}/fingerprints/{$fp->id}")
             ->assertStatus(404);
    }
}
