<?php

namespace Tests\Feature;

use App\Models\FaceTemplate;
use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FaceService;
use App\Services\FingerprintService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests for POST /api/verify/multimodal — the decision-matrix flow:
 * face identify → top-5 hospital shortlist → fingerprint match against
 * only the shortlisted patients → matched / needs_review / no_match.
 */
class MultimodalVerifyTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/verify/multimodal';

    private Hospital $hospital;
    private User $nurse;
    private Patient $patientA;
    private Patient $patientB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->hospital = Hospital::factory()->create([
            'face_recognition_enabled' => true,
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);
        $this->nurse    = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
        $this->patientA = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $this->patientB = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private function faceTemplate(Patient $patient): FaceTemplate
    {
        $ft = new FaceTemplate([
            'patient_id'    => $patient->id,
            'hospital_id'   => $this->hospital->id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $ft->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $ft->save();

        return $ft;
    }

    private function fingerprint(Patient $patient): Fingerprint
    {
        return Fingerprint::factory()->create([
            'patient_id'  => $patient->id,
            'hospital_id' => $this->hospital->id,
            'enrolled_by' => $this->nurse->id,
        ]);
    }

    /** Stub the face stage: liveness ok, embedding ok, FAISS returns $candidates. */
    private function mockFaceStage(array $candidates): void
    {
        $this->mock(FaceService::class, function ($mock) use ($candidates) {
            $mock->shouldReceive('liveness')->once()->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()
                ->andReturn(['embedding' => array_fill(0, 8, 0.1), 'face_detected' => true]);
            $mock->shouldReceive('identify')->once()->andReturn(['candidates' => $candidates]);
        });
    }

    private function payload(): array
    {
        return [
            'face_image'        => base64_encode('face'),
            'fingerprint_image' => base64_encode('finger'),
        ];
    }

    // ── Decision matrix ─────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function fingerprint_confirming_a_shortlisted_patient_returns_matched(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $ftB = $this->faceTemplate($this->patientB);
        $fpA = $this->fingerprint($this->patientA);
        $fpB = $this->fingerprint($this->patientB);

        // A patient outside the face shortlist must never reach the matcher.
        $outsider   = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $fpOutsider = $this->fingerprint($outsider);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.85],
            ['patient_id' => $this->patientB->id, 'template_id' => $ftB->id, 'score' => 0.55],
        ]);

        $this->mock(FingerprintService::class, function ($mock) use ($fpA, $fpB, $fpOutsider) {
            $mock->shouldReceive('process')->once()
                ->andReturn(['template' => ['minutiae' => []], 'quality_score' => 0.8]);

            $mock->shouldReceive('match')->once()
                ->withArgs(function ($probe, $candidates) use ($fpA, $fpB, $fpOutsider) {
                    $ids = array_column($candidates, 'patient_id'); // keyed by fingerprint id
                    return in_array($fpA->id, $ids)
                        && in_array($fpB->id, $ids)
                        && ! in_array($fpOutsider->id, $ids);
                })
                ->andReturn(['patient_id' => $fpA->id, 'score' => 45.0]);
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'matched')
            ->assertJsonPath('patient.id', $this->patientA->id)
            ->assertJsonPath('fingerprint_score', 45)
            ->assertJsonPath('face_score', 0.85);

        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $this->patientA->id,
            'status'     => 'matched',
            'modality'   => 'multimodal',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function unconfirmed_fingerprint_escalates_to_needs_review_not_rejection(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $this->fingerprint($this->patientA);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.70],
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()
                ->andReturn(['template' => ['minutiae' => []], 'quality_score' => 0.8]);
            $mock->shouldReceive('match')->once()
                ->andReturn(['patient_id' => 0, 'score' => 8.0]); // below threshold
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'needs_review')
            ->assertJsonPath('patient.id', $this->patientA->id);

        $this->assertDatabaseHas('verification_logs', [
            'status'   => 'needs_review',
            'modality' => 'multimodal',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function fingerprint_stage_failure_still_escalates_to_needs_review(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $this->fingerprint($this->patientA);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.80],
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->once()
                ->andThrow(new \RuntimeException('Python /process failed'));
            $mock->shouldReceive('match')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'needs_review')
            ->assertJsonPath('patient.id', $this->patientA->id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function empty_face_shortlist_returns_no_match_without_running_fingerprint(): void
    {
        $this->mockFaceStage([]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->never();
            $mock->shouldReceive('match')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match')
            ->assertJsonPath('patient', null);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function candidates_from_other_hospitals_are_excluded_from_the_shortlist(): void
    {
        $otherHospital = Hospital::factory()->create(['face_recognition_enabled' => true]);
        $foreign       = Patient::factory()->create(['hospital_id' => $otherHospital->id]);

        $foreignTemplate = new FaceTemplate([
            'patient_id'    => $foreign->id,
            'hospital_id'   => $otherHospital->id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $foreignTemplate->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $foreignTemplate->save();

        // FAISS is global — it may return another hospital's template, but
        // the shortlist must drop it.
        $this->mockFaceStage([
            ['patient_id' => $foreign->id, 'template_id' => $foreignTemplate->id, 'score' => 0.95],
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('process')->never();
            $mock->shouldReceive('match')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denied_outside_geofence(): void
    {
        $this->hospital->update(['wifi_ssid' => 'HOSPITAL-STAFF']);

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload() + ['wifi_ssid' => 'PUBLIC-WIFI'])
            ->assertStatus(403);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function rejected_when_face_recognition_is_disabled(): void
    {
        $this->hospital->update(['face_recognition_enabled' => false]);

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(403);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function failed_liveness_rejects_the_request(): void
    {
        $this->mock(FaceService::class, function ($mock) {
            $mock->shouldReceive('liveness')->once()
                ->andReturn(['is_live' => false, 'reason' => 'static_image']);
            $mock->shouldReceive('process')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(422);
    }
}
