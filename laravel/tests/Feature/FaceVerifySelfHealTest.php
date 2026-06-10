<?php

namespace Tests\Feature;

use App\Models\FaceTemplate;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\FaceService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests for the FAISS self-heal in POST /api/face/verify.
 *
 * When the Python service's on-disk index is lost (ephemeral-disk redeploy),
 * identify() returns zero candidates even though active face templates exist
 * in the database. The controller must rebuild the index from the encrypted
 * templates and retry the identification once.
 */
class FaceVerifySelfHealTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/face/verify';

    private Hospital $hospital;
    private User $nurse;
    private Patient $patient;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create([
            'face_recognition_enabled' => true,
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);
        $this->nurse   = User::factory()->nurse()->create(['hospital_id' => $this->hospital->id]);
        $this->patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
    }

    private function activeTemplate(): FaceTemplate
    {
        $ft = new FaceTemplate([
            'patient_id'    => $this->patient->id,
            'hospital_id'   => $this->hospital->id,
            'enrolled_by'   => $this->nurse->id,
            'quality_score' => 0.9,
            'is_active'     => true,
        ]);
        $ft->setTemplate(['embedding' => array_fill(0, 8, 0.1)]);
        $ft->save();

        return $ft;
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function empty_index_with_existing_templates_triggers_rebuild_and_retry(): void
    {
        $template = $this->activeTemplate();

        $this->mock(FaceService::class, function ($mock) use ($template) {
            $mock->shouldReceive('liveness')->once()
                ->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()
                ->andReturn(['embedding' => array_fill(0, 8, 0.1), 'face_detected' => true]);

            // First identify: index lost → empty. After rebuild: confident match.
            $mock->shouldReceive('identify')->twice()->andReturn(
                ['candidates' => []],
                ['candidates' => [[
                    'patient_id'  => $template->patient_id,
                    'template_id' => $template->id,
                    'score'       => 0.85,
                ]]],
            );

            $mock->shouldReceive('rebuildIndex')->once()
                ->withArgs(fn (array $templates) => count($templates) === 1)
                ->andReturn(1);
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'matched')
            ->assertJsonPath('patient.id', $this->patient->id);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function no_templates_means_no_rebuild_attempt(): void
    {
        $this->mock(FaceService::class, function ($mock) {
            $mock->shouldReceive('liveness')->once()->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()
                ->andReturn(['embedding' => array_fill(0, 8, 0.1), 'face_detected' => true]);
            $mock->shouldReceive('identify')->once()->andReturn(['candidates' => []]);
            $mock->shouldReceive('rebuildIndex')->never();
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function failed_rebuild_degrades_to_no_match_instead_of_erroring(): void
    {
        $this->activeTemplate();

        $this->mock(FaceService::class, function ($mock) {
            $mock->shouldReceive('liveness')->once()->andReturn(['is_live' => true]);
            $mock->shouldReceive('process')->once()
                ->andReturn(['embedding' => array_fill(0, 8, 0.1), 'face_detected' => true]);
            $mock->shouldReceive('identify')->once()->andReturn(['candidates' => []]);
            $mock->shouldReceive('rebuildIndex')->once()
                ->andThrow(new \RuntimeException('Python /face/rebuild failed'));
        });

        $this->actingAs($this->nurse)
            ->postJson(self::URL, ['image' => base64_encode('probe')])
            ->assertStatus(200)
            ->assertJsonPath('status', 'no_match');
    }
}
