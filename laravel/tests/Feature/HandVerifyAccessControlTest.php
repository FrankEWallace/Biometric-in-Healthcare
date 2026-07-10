<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FingerprintService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Plan 005 — the four-finger hand path resolves identity NATIONALLY (no
 * hospital pre-filter in loadCandidateHands), then applies the SAME shared
 * access-control step as the face path. A cross-hospital hit returns
 * `access_restricted` with the identical vocabulary the face path uses, no
 * PII, and an audit carrying the identified patient id.
 */
class HandVerifyAccessControlTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/verify/hand';

    private Hospital $hospital;
    private User $nurse;

    protected function setUp(): void
    {
        parent::setUp();
        // A calibrated embedding threshold so the placeholder-safe gate can
        // reach an auto-accept decision.
        config(['services.fingerprint.contactless_match_threshold' => 57.5]);

        $this->hospital = Hospital::factory()->create([
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);
        $this->nurse = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
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

    private function mockHand(int $matchedPatientId, float $score): void
    {
        $this->mock(FingerprintService::class, function ($mock) use ($matchedPatientId, $score) {
            $mock->shouldReceive('processHand')->once()->andReturn([
                'matcher' => 'ridgeformer_embedding',
                'domain'  => 'contactless',
                'fingers' => [
                    ['finger_position' => 'right_index',  'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_middle', 'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_ring',   'template' => ['format' => 'embedding']],
                ],
            ]);
            $mock->shouldReceive('matchHand')->once()->andReturn([
                'patient_id' => $matchedPatientId,
                'score'      => $score,
                'matcher'    => 'ridgeformer_embedding',
                'per_finger' => [],
            ]);
        });
    }

    private function payload(): array
    {
        return ['image' => base64_encode('hand'), 'hand' => 'right'];
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function same_hospital_hand_match_returns_matched(): void
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $this->enrollHand($patient);
        $this->mockHand($patient->id, 78.0);

        $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('status', 'matched')
            ->assertJsonPath('patient.id', $patient->id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function cross_hospital_hand_match_is_access_restricted(): void
    {
        $otherHospital = Hospital::factory()->create();
        $patient = Patient::factory()->create(['hospital_id' => $otherHospital->id]);
        $this->enrollHand($patient);
        $this->mockHand($patient->id, 90.0);

        $response = $this->actingAs($this->nurse)
            ->postJson(self::URL, $this->payload())
            ->assertStatus(200)
            // Same status vocabulary as the face path — the consistency guarantee.
            ->assertJsonPath('status', 'access_restricted');

        // No cross-hospital PII to the client.
        $this->assertNull($response->json('patient'));
        $this->assertNull($response->json('candidate_patient_id'));

        // Audit + verification log record the identified patient id.
        $this->assertDatabaseHas('audit_logs', [
            'action'     => AuditLog::ACTION_ACCESS_RESTRICTED,
            'patient_id' => $patient->id,
            'staff_id'   => $this->nurse->id,
        ]);
        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $patient->id,
            'status'     => 'access_restricted',
            'modality'   => 'hand',
        ]);
    }
}
