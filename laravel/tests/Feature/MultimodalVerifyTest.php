<?php

namespace Tests\Feature;

use App\Models\AuditLog;
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
 * face identify → top-5 hospital shortlist → four-finger hand match against
 * only the shortlisted patients → matched / needs_review / no_match.
 *
 * The fingerprint-confirm step uses the SAME four-finger contactless embedding
 * pipeline as /verify/hand (processHand → matchHand), so it is placeholder-safe:
 * it only auto-confirms when a calibrated contactless threshold is configured
 * AND the matcher that ran is a learned embedding.
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

        // A calibrated embedding threshold so the placeholder-safe gate can
        // reach an auto-accept decision.
        config(['services.fingerprint.contactless_match_threshold' => 57.5]);

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

    /** Enroll >= MIN_HAND_FINGERS gallery-lead templates so the patient is a candidate. */
    private function enrollHand(Patient $patient): void
    {
        foreach (['right_index', 'right_middle', 'right_ring'] as $position) {
            Fingerprint::factory()->create([
                'patient_id'      => $patient->id,
                'hospital_id'     => $patient->hospital_id,
                'enrolled_by'     => $this->nurse->id,
                'finger_position' => $position,
                'is_gallery_lead' => true,
                'is_active'       => true,
            ]);
        }
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

    /** Stub the hand fingerprint-confirm stage: probe segments + a fused match. */
    private function mockHandConfirm(callable $matchArgs, int $matchedPatientId, float $score): void
    {
        $this->mock(FingerprintService::class, function ($mock) use ($matchArgs, $matchedPatientId, $score) {
            $mock->shouldReceive('processHand')->once()->andReturn([
                'matcher' => 'ridgeformer_embedding',
                'domain'  => 'contactless',
                'fingers' => [
                    ['finger_position' => 'right_index',  'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_middle', 'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_ring',   'template' => ['format' => 'embedding']],
                ],
            ]);
            $mock->shouldReceive('matchHand')->once()
                ->withArgs($matchArgs)
                ->andReturn([
                    'patient_id' => $matchedPatientId,
                    'score'      => $score,
                    'matcher'    => 'ridgeformer_embedding',
                    'per_finger' => [],
                ]);
        });
    }

    private function payload(): array
    {
        return [
            'face_image'        => base64_encode('face'),
            'fingerprint_image' => base64_encode('finger'),
            'hand'              => 'right',
        ];
    }

    // ── Decision matrix ─────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function fingerprint_confirming_a_shortlisted_patient_returns_matched(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $ftB = $this->faceTemplate($this->patientB);
        $this->enrollHand($this->patientA);
        $this->enrollHand($this->patientB);

        // A patient outside the face shortlist must never reach the matcher.
        $outsider = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $this->enrollHand($outsider);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.85],
            ['patient_id' => $this->patientB->id, 'template_id' => $ftB->id, 'score' => 0.55],
        ]);

        // Candidate hands are keyed by patient_id and scoped to the shortlist —
        // the outsider must never appear among them.
        $this->mockHandConfirm(
            function ($probe, $candidates) use ($outsider) {
                $ids = array_column($candidates, 'patient_id');
                return in_array($this->patientA->id, $ids)
                    && in_array($this->patientB->id, $ids)
                    && ! in_array($outsider->id, $ids);
            },
            matchedPatientId: $this->patientA->id,
            score: 72.0, // >= configured contactless threshold (57.5)
        );

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'matched')
            ->assertJsonPath('patient.id', $this->patientA->id)
            ->assertJsonPath('fingerprint_score', 72)
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
        $this->enrollHand($this->patientA);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.70],
        ]);

        // Fused score below the configured contactless threshold (57.5).
        $this->mockHandConfirm(fn ($probe, $candidates) => true, matchedPatientId: 0, score: 8.0);

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
    public function placeholder_matcher_never_auto_confirms_even_above_threshold(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $this->enrollHand($this->patientA);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.80],
        ]);

        // Minutiae placeholder (matcher name lacks "embedding") — must NOT
        // auto-confirm even with a high fused score.
        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('processHand')->once()->andReturn([
                'matcher' => 'minutiae_sourceafis',
                'domain'  => 'contactless',
                'fingers' => [
                    ['finger_position' => 'right_index',  'template' => ['format' => 'minutiae']],
                    ['finger_position' => 'right_middle', 'template' => ['format' => 'minutiae']],
                    ['finger_position' => 'right_ring',   'template' => ['format' => 'minutiae']],
                ],
            ]);
            $mock->shouldReceive('matchHand')->once()->andReturn([
                'patient_id' => $this->patientA->id,
                'score'      => 99.0,
                'matcher'    => 'minutiae_sourceafis',
                'per_finger' => [],
            ]);
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'needs_review');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function fingerprint_stage_failure_still_escalates_to_needs_review(): void
    {
        $ftA = $this->faceTemplate($this->patientA);
        $this->enrollHand($this->patientA);

        $this->mockFaceStage([
            ['patient_id' => $this->patientA->id, 'template_id' => $ftA->id, 'score' => 0.80],
        ]);

        $this->mock(FingerprintService::class, function ($mock) {
            $mock->shouldReceive('processHand')->once()
                ->andThrow(new \RuntimeException('Python /process-hand failed'));
            $mock->shouldReceive('matchHand')->never();
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
            $mock->shouldReceive('processHand')->never();
            $mock->shouldReceive('matchHand')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match')
            ->assertJsonPath('patient', null);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function cross_hospital_identity_returns_access_restricted_without_pii(): void
    {
        // Identity is resolved NATIONALLY: FAISS is global and the shortlist no
        // longer drops foreign templates. A cross-hospital patient whose face
        // and hand both hit is identified, then access-gated by
        // PatientAccessService — yielding access_restricted (identity found,
        // records withheld), never a fake no_match. Mirrors the /verify/hand
        // contract in HandVerifyAccessControlTest.
        $otherHospital = Hospital::factory()->create(['face_recognition_enabled' => true]);
        $foreign       = Patient::factory()->create(['hospital_id' => $otherHospital->id]);
        $this->enrollHand($foreign);

        $foreignTemplate = new FaceTemplate([
            'patient_id'    => $foreign->id,
            'hospital_id'   => $otherHospital->id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $foreignTemplate->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $foreignTemplate->save();

        $this->mockFaceStage([
            ['patient_id' => $foreign->id, 'template_id' => $foreignTemplate->id, 'score' => 0.95],
        ]);

        // Hand confirms the national foreign candidate above threshold.
        $this->mockHandConfirm(
            fn ($probe, $candidates) => in_array($foreign->id, array_column($candidates, 'patient_id')),
            matchedPatientId: $foreign->id,
            score: 80.0,
        );

        $response = $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'access_restricted');

        // No cross-hospital PII or clinical records leak to the client.
        $this->assertNull($response->json('patient'));
        $this->assertNull($response->json('ehr'));
        $this->assertNull($response->json('insurance'));

        // Audit + verification log keep the identified patient id server-side.
        $this->assertDatabaseHas('audit_logs', [
            'action'     => AuditLog::ACTION_ACCESS_RESTRICTED,
            'patient_id' => $foreign->id,
            'staff_id'   => $this->nurse->id,
        ]);
        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $foreign->id,
            'status'     => 'access_restricted',
            'modality'   => 'multimodal',
        ]);
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
