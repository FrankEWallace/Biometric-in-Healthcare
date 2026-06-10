<?php

namespace Tests\Feature;

use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FingerprintService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Tests for the multi-capture "gallery of 3" enrollment endpoint
 * (POST /api/fingerprint/enroll-gallery).
 *
 * Design decisions exercised here:
 *   - Up to 3 captures per finger stored as a gallery
 *   - Highest-quality capture flagged is_gallery_lead (the 1:N representative)
 *   - is_primary applied only to the lead of the primary finger
 *   - Floor of 1: ≥1 usable capture enrolls; 0 usable → 422 no_usable_capture
 *   - Fewer than 3 usable → needs_reenrollment flag set
 *   - A single-use server-issued liveness token gates the whole batch
 *   - Re-enrolling a finger replaces its previous gallery (no accumulation)
 *
 * See .claude/grill-sessions/2026-06-05-multi-capture-fingerprint-enrollment.md
 */
class EnrollGalleryTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/fingerprint/enroll-gallery';

    private Hospital $hospital;
    private User $nurse;
    private Patient $patient;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create();
        $this->nurse    = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
        $this->patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    /** A successful Python /process-fingerprint result with the given quality. */
    private function okResult(float $quality, int $keypoints = 24): array
    {
        return [
            'success'       => true,
            'quality_score' => $quality,
            'steps_applied' => [],
            'features'      => [
                'status'         => 'ok',
                'keypoint_count' => $keypoints,
                'keypoints'      => [],
                'descriptors'    => [],
            ],
        ];
    }

    /** A result where no fingerprint features could be extracted. */
    private function noFeaturesResult(): array
    {
        return [
            'success'       => true,
            'quality_score' => 0.50,
            'features'      => ['status' => 'no_features', 'keypoint_count' => 0],
        ];
    }

    /** @param int $n number of fake capture images */
    private function fakeCaptures(int $n): array
    {
        return collect(range(1, $n))
            ->map(fn ($i) => UploadedFile::fake()->image("capture{$i}.jpg"))
            ->all();
    }

    /**
     * Mint a liveness token the way livenessCheck() does — cached, single
     * use, bound to the user who passed the optical-flow check.
     */
    private function livenessToken(?User $user = null): string
    {
        $token = Str::random(48);
        Cache::put(
            'fp_liveness_token:' . $token,
            ($user ?? $this->nurse)->id,
            now()->addMinutes(10),
        );

        return $token;
    }

    // ── Happy path + lead selection ─────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function gallery_stores_all_captures_and_flags_highest_quality_as_lead(): void
    {
        // Captures returned in order 0.50, 0.90, 0.70 — the 0.90 one must lead.
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->times(3)->andReturn(
                $this->okResult(0.50),
                $this->okResult(0.90),
                $this->okResult(0.70),
            );
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'      => $this->patient->id,
                'finger_position' => 'right_index',
                'captures'        => $this->fakeCaptures(3),
                'liveness_token'  => $this->livenessToken(),
            ])
            ->assertStatus(201)
            ->assertJsonPath('gallery_size', 3)
            ->assertJsonPath('needs_reenrollment', false)
            ->assertJsonPath('lead_quality_score', 0.9);

        // Exactly 3 rows for the finger, exactly one lead, and the lead is 0.90.
        $rows = Fingerprint::where('patient_id', $this->patient->id)
            ->where('finger_position', 'right_index')->get();

        $this->assertCount(3, $rows);
        $this->assertCount(1, $rows->where('is_gallery_lead', true));
        $this->assertEquals(0.90, $rows->firstWhere('is_gallery_lead', true)->quality_score);
    }

    // ── Degraded coverage ───────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function fewer_than_three_usable_captures_sets_needs_reenrollment(): void
    {
        // Middle capture yields no features → only 2 usable.
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->times(3)->andReturn(
                $this->okResult(0.60),
                $this->noFeaturesResult(),
                $this->okResult(0.80),
            );
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(3),
                'liveness_token' => $this->livenessToken(),
            ])
            ->assertStatus(201)
            ->assertJsonPath('gallery_size', 2)
            ->assertJsonPath('needs_reenrollment', true)
            ->assertJsonCount(1, 'rejected');

        $this->assertDatabaseCount('fingerprints', 2);
        $this->assertDatabaseHas('fingerprints', [
            'patient_id'         => $this->patient->id,
            'needs_reenrollment' => true,
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function single_usable_capture_still_enrolls_floor_of_one(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->once()->andReturn($this->okResult(0.55));
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(1),
                'liveness_token' => $this->livenessToken(),
            ])
            ->assertStatus(201)
            ->assertJsonPath('gallery_size', 1)
            ->assertJsonPath('needs_reenrollment', true);

        // The lone capture is its own lead.
        $this->assertDatabaseHas('fingerprints', [
            'patient_id'      => $this->patient->id,
            'is_gallery_lead' => true,
        ]);
    }

    // ── Zero usable → face-fallback signal ──────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function no_usable_capture_returns_422_with_fallback_code(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->times(2)->andReturn(
                $this->noFeaturesResult(),
                $this->okResult(0.05),   // below MIN_QUALITY_SCORE (0.10)
            );
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(2),
                'liveness_token' => $this->livenessToken(),
            ])
            ->assertStatus(422)
            ->assertJsonPath('code', 'no_usable_capture')
            ->assertJsonCount(2, 'rejected');

        $this->assertDatabaseCount('fingerprints', 0);
    }

    // ── Liveness gate ───────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function missing_liveness_token_fails_validation(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, [
                'patient_id' => $this->patient->id,
                'captures'   => $this->fakeCaptures(3),
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['liveness_token']);

        $this->assertDatabaseCount('fingerprints', 0);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function forged_liveness_token_rejects_the_whole_batch(): void
    {
        // register must never be called when the token is not server-issued.
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->never();
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(3),
                'liveness_token' => 'not-a-real-token',
            ])
            ->assertStatus(422)
            ->assertJsonPath('code', 'liveness_required');

        $this->assertDatabaseCount('fingerprints', 0);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function liveness_token_issued_to_another_user_is_rejected(): void
    {
        $otherNurse = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->never();
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(1),
                'liveness_token' => $this->livenessToken($otherNurse),
            ])
            ->assertStatus(422)
            ->assertJsonPath('code', 'liveness_required');

        $this->assertDatabaseCount('fingerprints', 0);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function liveness_token_is_single_use(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->once()->andReturn($this->okResult(0.70));
        });

        $token   = $this->livenessToken();
        $payload = [
            'patient_id'     => $this->patient->id,
            'captures'       => $this->fakeCaptures(1),
            'liveness_token' => $token,
        ];

        $this->actingAs($this->nurse)->post(self::URL, $payload)->assertStatus(201);

        // Replaying the same token must fail — it was consumed above.
        $payload['captures'] = $this->fakeCaptures(1);
        $this->actingAs($this->nurse)
            ->post(self::URL, $payload)
            ->assertStatus(422)
            ->assertJsonPath('code', 'liveness_required');

        $this->assertDatabaseCount('fingerprints', 1);
    }

    // ── Geofence gate ───────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function enrollment_is_denied_outside_the_hospital_geofence(): void
    {
        $this->hospital->update(['wifi_ssid' => 'HOSPITAL-STAFF']);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->never();
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(1),
                'liveness_token' => $this->livenessToken(),
                'wifi_ssid'      => 'PUBLIC-WIFI',
            ])
            ->assertStatus(403)
            ->assertJsonPath('code', 'geofence_denied');

        $this->assertDatabaseCount('fingerprints', 0);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function enrollment_is_allowed_inside_the_hospital_geofence(): void
    {
        $this->hospital->update(['wifi_ssid' => 'HOSPITAL-STAFF']);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->once()->andReturn($this->okResult(0.70));
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $this->patient->id,
                'captures'       => $this->fakeCaptures(1),
                'liveness_token' => $this->livenessToken(),
                'wifi_ssid'      => 'HOSPITAL-STAFF',
            ])
            ->assertStatus(201);

        $this->assertDatabaseCount('fingerprints', 1);
    }

    // ── Primary flag ────────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function is_primary_lands_only_on_the_lead_and_demotes_previous_primary(): void
    {
        // Existing primary on another finger that must be demoted.
        $existing = Fingerprint::factory()->create([
            'patient_id'      => $this->patient->id,
            'hospital_id'     => $this->hospital->id,
            'enrolled_by'     => $this->nurse->id,
            'finger_position' => 'left_index',
            'is_primary'      => true,
            'is_gallery_lead' => true,
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->times(3)->andReturn(
                $this->okResult(0.40),
                $this->okResult(0.95),   // lead
                $this->okResult(0.60),
            );
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'      => $this->patient->id,
                'finger_position' => 'right_index',
                'is_primary'      => true,
                'captures'        => $this->fakeCaptures(3),
                'liveness_token'  => $this->livenessToken(),
            ])
            ->assertStatus(201)
            ->assertJsonPath('is_primary', true);

        // Previous primary demoted.
        $this->assertDatabaseHas('fingerprints', ['id' => $existing->id, 'is_primary' => false]);

        // Exactly one primary across the whole patient, and it is the lead row.
        $primaries = Fingerprint::where('patient_id', $this->patient->id)
            ->where('is_primary', true)->get();

        $this->assertCount(1, $primaries);
        $this->assertTrue($primaries->first()->is_gallery_lead);
        $this->assertEquals(0.95, $primaries->first()->quality_score);
    }

    // ── Re-enrollment replaces the gallery ──────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function re_enrolling_a_finger_replaces_its_previous_gallery(): void
    {
        $this->mock(FingerprintService::class, function ($mock) {
            // First enrollment: 3 captures. Second: 2 captures.
            $mock->shouldReceive('register')->times(5)->andReturn(
                $this->okResult(0.50),
                $this->okResult(0.60),
                $this->okResult(0.70),
                $this->okResult(0.80),
                $this->okResult(0.90),
            );
        });

        $payload = fn (int $n) => [
            'patient_id'      => $this->patient->id,
            'finger_position' => 'right_index',
            'captures'        => $this->fakeCaptures($n),
            'liveness_token'  => $this->livenessToken(),
        ];

        $this->actingAs($this->nurse)->post(self::URL, $payload(3))->assertStatus(201);
        $this->actingAs($this->nurse)->post(self::URL, $payload(2))->assertStatus(201);

        // Old gallery of 3 replaced by the new gallery of 2 — no accumulation.
        $this->assertDatabaseCount('fingerprints', 2);
        $this->assertEquals(
            1,
            Fingerprint::where('patient_id', $this->patient->id)
                ->where('finger_position', 'right_index')
                ->where('is_gallery_lead', true)->count()
        );
    }

    // ── Validation & scope ──────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function rejects_more_than_three_captures(): void
    {
        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id' => $this->patient->id,
                'captures'   => $this->fakeCaptures(4),
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['captures']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function requires_at_least_one_capture(): void
    {
        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['patient_id' => $this->patient->id])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['captures']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function rejects_invalid_finger_position(): void
    {
        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'      => $this->patient->id,
                'finger_position' => 'left_ear',
                'captures'        => $this->fakeCaptures(1),
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['finger_position']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function returns_404_for_patient_at_different_hospital(): void
    {
        $otherHospital  = Hospital::factory()->create();
        $foreignPatient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('register')->andReturn($this->okResult(0.80));
        });

        $this->actingAs($this->nurse)
            ->post(self::URL, [
                'patient_id'     => $foreignPatient->id,
                'captures'       => $this->fakeCaptures(1),
                'liveness_token' => $this->livenessToken(),
            ])
            ->assertStatus(404);

        $this->assertDatabaseCount('fingerprints', 0);
    }
}
