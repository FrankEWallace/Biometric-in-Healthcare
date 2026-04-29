<?php

namespace Tests\Feature;

use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FingerprintService;
use App\Services\GeofenceService;
use App\Services\HomisService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * Tests covering VerificationController failure paths (POST /api/verify).
 *
 * Failure modes exercised:
 *   - Geofence denial (device outside GPS radius)
 *   - Geofence denial (wrong WiFi SSID)
 *   - Missing image field
 *   - Python /process throws (feature extraction failure)
 *   - No fingerprints enrolled → no_match
 *   - All fingerprints inactive → no_match
 *   - Score below MATCH_THRESHOLD (0.35) → no_match
 *   - Score at or above threshold → matched
 *   - GoT-HoMIS failure is non-fatal (verification still succeeds)
 *   - Audit log is written for every attempt (matched and no_match)
 *   - Unauthenticated request returns 401
 */
class VerificationTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $operator;

    protected function setUp(): void
    {
        parent::setUp();

        // Hospital with no geofencing by default so most tests pass freely
        $this->hospital = Hospital::factory()->create([
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);

        $this->operator = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
    }

    // ── Auth guard ────────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_401_when_unauthenticated(): void
    {
        $this->postJson('/api/verify', ['image' => base64_encode('data')])
             ->assertStatus(401);
    }

    // ── Input validation ──────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_fails_when_image_is_missing(): void
    {
        $this->actingAs($this->operator)
             ->postJson('/api/verify', [])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['image']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_fails_when_gps_latitude_is_out_of_range(): void
    {
        $this->actingAs($this->operator)
             ->postJson('/api/verify', [
                 'image'        => base64_encode('img'),
                 'gps_latitude' => 91.0,   // valid range is -90 to 90
             ])
             ->assertStatus(422)
             ->assertJsonValidationErrors(['gps_latitude']);
    }

    // ── Geofence denial ───────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_is_denied_when_device_is_outside_gps_radius(): void
    {
        // Hospital centred at Sarajevo; device reports Mostar coordinates
        $this->hospital->update([
            'gps_latitude'      => 43.8563,
            'gps_longitude'     => 18.4131,
            'gps_radius_meters' => 300,
        ]);

        $this->actingAs($this->operator)
             ->postJson('/api/verify', [
                 'image'         => base64_encode('img'),
                 'gps_latitude'  => 43.3438,   // Mostar — ~57 km away
                 'gps_longitude' => 17.8078,
             ])
             ->assertStatus(403)
             ->assertJsonFragment(['error' => 'Access denied: device is not within hospital premises.']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_is_denied_when_wifi_ssid_does_not_match(): void
    {
        $this->hospital->update(['wifi_ssid' => 'HOSPITAL-STAFF']);

        $this->actingAs($this->operator)
             ->postJson('/api/verify', [
                 'image'     => base64_encode('img'),
                 'wifi_ssid' => 'PUBLIC-WIFI',
             ])
             ->assertStatus(403);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_is_denied_when_wifi_configured_but_no_ssid_provided(): void
    {
        $this->hospital->update(['wifi_ssid' => 'HOSPITAL-STAFF']);

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(403);
    }

    // ── Python microservice failure ───────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_500_when_python_process_endpoint_is_down(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')
                 ->once()
                 ->andThrow(new RuntimeException('Connection refused'));
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(500)
             ->assertJsonPath('error', fn ($v) => str_contains($v, 'Feature extraction failed'));
    }

    // ── No enrolled fingerprints ──────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_no_match_when_no_fingerprints_are_enrolled(): void
    {
        // Patient exists but has zero fingerprints
        Patient::factory()->create(['hospital_id' => $this->hospital->id]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
            // match() should NOT be called — no candidates to send
            $mock->shouldNotReceive('match');
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(200)
             ->assertJsonPath('status', 'no_match');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_no_match_when_all_fingerprints_are_inactive(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        Fingerprint::factory()->inactive()->create([
            'patient_id'  => $patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->operator->id,
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
            $mock->shouldNotReceive('match');
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(200)
             ->assertJsonPath('status', 'no_match');
    }

    // ── Score threshold ───────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_no_match_when_score_is_below_threshold(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $fp      = Fingerprint::factory()->primary()->create([
            'patient_id'  => $patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->operator->id,
        ]);

        $this->mock(FingerprintService::class, function ($mock) use ($fp) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
            $mock->shouldReceive('match')->once()->andReturn([
                'patient_id' => $fp->id,
                'score'      => 0.20,   // below MATCH_THRESHOLD = 0.35
            ]);
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(200)
             ->assertJsonPath('status', 'no_match');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_returns_matched_when_score_meets_threshold(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $fp      = Fingerprint::factory()->primary()->create([
            'patient_id'  => $patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->operator->id,
        ]);

        $this->mock(HomisService::class, function ($mock) {
            $mock->shouldReceive('getPatientRecord')->andReturn(null);
            $mock->shouldReceive('getInsuranceEligibility')->andReturn(null);
        });

        $this->mock(FingerprintService::class, function ($mock) use ($fp) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
            $mock->shouldReceive('match')->once()->andReturn([
                'patient_id' => $fp->id,
                'score'      => 0.90,   // well above threshold
            ]);
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(200)
             ->assertJsonPath('status', 'matched')
             ->assertJsonPath('patient.id', $patient->id);
    }

    // ── GoT-HoMIS non-fatal failure ───────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verify_succeeds_even_when_homis_is_unreachable(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $fp      = Fingerprint::factory()->primary()->create([
            'patient_id'  => $patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->operator->id,
        ]);

        // HomisService returns null (network timeout / unavailable)
        $this->mock(HomisService::class, function ($mock) {
            $mock->shouldReceive('getPatientRecord')->andReturn(null);
            $mock->shouldReceive('getInsuranceEligibility')->andReturn(null);
        });

        $this->mock(FingerprintService::class, function ($mock) use ($fp) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
            $mock->shouldReceive('match')->once()->andReturn([
                'patient_id' => $fp->id,
                'score'      => 0.90,
            ]);
        });

        $response = $this->actingAs($this->operator)
                         ->postJson('/api/verify', ['image' => base64_encode('img')]);

        $response->assertStatus(200)
                 ->assertJsonPath('status', 'matched')
                 ->assertJsonPath('ehr', null)
                 ->assertJsonPath('insurance', null);
    }

    // ── Audit log written on every attempt ────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function verification_log_is_created_for_no_match_attempt(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()->andReturn([
                'template'      => ['keypoints' => [], 'descriptors' => []],
                'quality_score' => 0.80,
            ]);
        });

        $this->actingAs($this->operator)
             ->postJson('/api/verify', ['image' => base64_encode('img')])
             ->assertStatus(200);

        $this->assertDatabaseHas('verification_logs', [
            'hospital_id' => $this->hospital->id,
            'operator_id' => $this->operator->id,
            'status'      => 'no_match',
        ]);
    }
}
