<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\FaceTemplate;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FaceService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Plan 005 — the face path resolves identity NATIONALLY, then applies the
 * shared access-control step. A cross-hospital hit must return
 * `access_restricted` (identity found, records withheld), never `no_match`,
 * carry no patient PII, and still audit the identified patient id.
 *
 * IDENTIFY_THRESHOLD = 0.40; review band starts at 0.32.
 */
class FaceVerifyAccessControlTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/face/verify';

    private Hospital $hospital;
    private User $nurse;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create([
            'face_recognition_enabled' => true,
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);
        $this->nurse = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
    }

    /** Active template for $patient; caller decides the patient's hospital. */
    private function templateFor(Patient $patient): FaceTemplate
    {
        $ft = new FaceTemplate([
            'patient_id'    => $patient->id,
            'hospital_id'   => $patient->hospital_id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $ft->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $ft->save();

        return $ft;
    }

    private function mockIdentify(FaceTemplate $template, float $score): void
    {
        $this->mock(FaceService::class, function ($mock) use ($template, $score) {
            $mock->shouldReceive('liveness')->once()->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()
                ->andReturn(['embedding' => array_fill(0, 8, 0.1), 'face_detected' => true]);
            $mock->shouldReceive('identify')->once()->andReturn(['candidates' => [[
                'patient_id'  => $template->patient_id,
                'template_id' => $template->id,
                'score'       => $score,
            ]]]);
        });
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function same_hospital_hit_above_threshold_is_matched(): void
    {
        $patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $template = $this->templateFor($patient);
        $this->mockIdentify($template, 0.85);

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'matched')
            ->assertJsonPath('patient.id', $patient->id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function cross_hospital_hit_is_access_restricted_not_no_match(): void
    {
        $otherHospital = Hospital::factory()->create();
        $patient  = Patient::factory()->create(['hospital_id' => $otherHospital->id]);
        $template = $this->templateFor($patient);
        // Higher score than any same-hospital candidate — proves identity is
        // resolved first and access is denied second (not hidden as no_match).
        $this->mockIdentify($template, 0.95);

        $response = $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'access_restricted');

        // No PII leaks to the client.
        $this->assertNull($response->json('patient'));
        $this->assertNull($response->json('ehr'));
        $this->assertNull($response->json('insurance'));

        // But the server audit records the identified patient id.
        $this->assertDatabaseHas('audit_logs', [
            'action'     => AuditLog::ACTION_ACCESS_RESTRICTED,
            'patient_id' => $patient->id,
            'staff_id'   => $this->nurse->id,
        ]);
        // And the verification log too (accountability trail).
        $this->assertDatabaseHas('verification_logs', [
            'patient_id' => $patient->id,
            'status'     => 'access_restricted',
            'modality'   => 'face',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function below_review_band_is_no_match(): void
    {
        $patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $template = $this->templateFor($patient);
        $this->mockIdentify($template, 0.20);

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match')
            ->assertJsonPath('patient', null);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function same_hospital_borderline_score_is_needs_review(): void
    {
        $patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $template = $this->templateFor($patient);
        $this->mockIdentify($template, 0.35); // 0.32 <= 0.35 < 0.40

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'needs_review')
            ->assertJsonPath('patient.id', $patient->id);
    }
}
