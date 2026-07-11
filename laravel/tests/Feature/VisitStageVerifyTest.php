<?php

namespace Tests\Feature;

use App\Models\FaceTemplate;
use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Models\Visit;
use App\Models\VisitStage;
use App\Services\FaceService;
use App\Services\FingerprintService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests for POST /api/visits/{visit}/stages/{stage}/verify — the stage
 * pipeline repointed so the four-finger hand embedding is the primary
 * matcher, face is the fallback, and single-finger contactless minutiae is
 * advisory-only (never completes a stage).
 */
class VisitStageVerifyTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $nurse;
    private Patient $patient;
    private Visit $visit;
    private VisitStage $stage;

    protected function setUp(): void
    {
        parent::setUp();

        // Threshold override — env-independent per plan Step 0.
        config(['services.fingerprint.contactless_match_threshold' => 57.5]);

        $this->hospital = Hospital::factory()->create([
            'face_recognition_enabled' => true,
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);
        $this->nurse   = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
        $this->patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);

        $this->visit = Visit::create([
            'hospital_id' => $this->hospital->id,
            'patient_id'  => $this->patient->id,
            'opened_by'   => $this->nurse->id,
            'visit_type'  => 'pending',
            'status'      => 'open',
            'opened_at'   => now(),
        ]);

        $this->stage = VisitStage::create([
            'visit_id' => $this->visit->id,
            'stage'    => 'triage',
            'status'   => 'pending',
        ]);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private function url(): string
    {
        return "/api/visits/{$this->visit->id}/stages/triage/verify";
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'hand_image' => base64_encode('hand'),
            'hand'       => 'right',
        ], $overrides);
    }

    /** Enroll >= MIN_HAND_FINGERS gallery-lead templates so loadPatientHand() succeeds. */
    private function enrollHand(Patient $patient): void
    {
        foreach (['right_index', 'right_middle', 'right_ring'] as $position) {
            Fingerprint::factory()->create([
                'patient_id'      => $patient->id,
                'hospital_id'     => $this->hospital->id,
                'enrolled_by'     => $this->nurse->id,
                'finger_position' => $position,
                'is_gallery_lead' => true,
                'is_active'       => true,
            ]);
        }
    }

    private function mockHandStage(array $matchResult): void
    {
        $this->mock(FingerprintService::class, function ($mock) use ($matchResult) {
            $mock->shouldReceive('processHand')->once()->andReturn([
                'matcher' => $matchResult['matcher'] ?? 'ridgeformer_embedding',
                'domain'  => 'contactless',
                'fingers' => [
                    ['finger_position' => 'right_index',  'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_middle', 'template' => ['format' => 'embedding']],
                    ['finger_position' => 'right_ring',   'template' => ['format' => 'embedding']],
                ],
            ]);
            $mock->shouldReceive('matchHand')->once()->andReturn($matchResult);
        });
    }

    // ── Decision matrix ─────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function hand_embedding_match_completes_the_stage(): void
    {
        $this->enrollHand($this->patient);
        $this->mockHandStage([
            'patient_id' => $this->patient->id,
            'score'      => 78.0,
            'matcher'    => 'ridgeformer_embedding',
        ]);

        $response = $this->actingAs($this->nurse)
            ->postJson($this->url(), $this->payload())
            ->assertStatus(200)
            ->assertJsonPath('matched', true)
            ->assertJsonPath('modality', 'hand');

        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $this->patient->id,
            'status'     => 'matched',
            'modality'   => 'hand',
        ]);

        $this->stage->refresh();
        $this->assertTrue($this->stage->isCompleted());
        $this->assertEquals($response->json('verification_log_id'), $this->stage->verification_log_id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function hand_needs_review_falls_back_to_face_and_completes(): void
    {
        $this->enrollHand($this->patient);
        // Threshold configured but matcher is still the placeholder — needs_review.
        $this->mockHandStage([
            'patient_id' => $this->patient->id,
            'score'      => 95.0,
            'matcher'    => 'minutiae_placeholder',
        ]);

        $faceTemplate = new FaceTemplate([
            'patient_id'    => $this->patient->id,
            'hospital_id'   => $this->hospital->id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $faceTemplate->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $faceTemplate->save();

        $this->mock(FaceService::class, function ($mock) {
            $mock->shouldReceive('liveness')->once()->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()->andReturn(['embedding' => array_fill(0, 8, 0.1)]);
            $mock->shouldReceive('match')->once()->andReturn(['score' => 0.9]);
        });

        $response = $this->actingAs($this->nurse)
            ->postJson($this->url(), $this->payload(['face_image' => base64_encode('face')]))
            ->assertStatus(200)
            ->assertJsonPath('matched', true)
            ->assertJsonPath('modality', 'face');

        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $this->patient->id,
            'status'     => 'matched',
            'modality'   => 'face',
        ]);

        $this->stage->refresh();
        $this->assertTrue($this->stage->isCompleted());
        $this->assertEquals($response->json('verification_log_id'), $this->stage->verification_log_id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function placeholder_matcher_with_high_score_never_completes_the_stage(): void
    {
        $this->enrollHand($this->patient);
        // High fused score, but matcher name doesn't contain 'embedding' —
        // proves minutiae/placeholder can't auto-accept even at a high score.
        $this->mockHandStage([
            'patient_id' => $this->patient->id,
            'score'      => 99.0,
            'matcher'    => 'minutiae-v1-placeholder',
        ]);

        $this->actingAs($this->nurse)
            ->postJson($this->url(), $this->payload())
            ->assertStatus(422)
            ->assertJsonPath('matched', false)
            ->assertJsonPath('fallback_exhausted', true);

        $this->stage->refresh();
        $this->assertFalse($this->stage->isCompleted());
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function all_tiers_fail_returns_fallback_exhausted_without_500(): void
    {
        $this->enrollHand($this->patient);
        $this->mockHandStage([
            'patient_id' => null,
            'score'      => 10.0,
            'matcher'    => 'ridgeformer_embedding',
        ]);

        $this->actingAs($this->nurse)
            ->postJson($this->url(), $this->payload())
            ->assertStatus(422)
            ->assertJsonPath('matched', false)
            ->assertJsonPath('fallback_exhausted', true);

        $this->stage->refresh();
        $this->assertFalse($this->stage->isCompleted());
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function patient_id_mismatch_despite_high_score_never_matches(): void
    {
        $this->enrollHand($this->patient);
        $otherPatient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);

        // Fused score is high and the matcher is the real embedding matcher,
        // but the returned patient_id belongs to someone else. Today the
        // candidate list contains only this visit's patient, so matchHand
        // "shouldn't" be able to return another ID — this guards the 1:1
        // invariant against future refactors (e.g. 1:N identification).
        $this->mockHandStage([
            'patient_id' => $otherPatient->id,
            'score'      => 95.0,
            'matcher'    => 'ridgeformer_embedding',
        ]);

        $this->actingAs($this->nurse)
            ->postJson($this->url(), $this->payload())
            ->assertStatus(422)
            ->assertJsonPath('matched', false);

        $this->stage->refresh();
        $this->assertFalse($this->stage->isCompleted());
    }
}
