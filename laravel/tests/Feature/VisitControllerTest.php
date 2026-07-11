<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Models\VerificationLog;
use App\Models\Visit;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Lifecycle coverage for the visit endpoints (open / close / reopen).
 *
 * Exists specifically to guard against a regression of the Visit timestamp
 * bug (plan 014): the `visits` table has no created_at/updated_at columns, so
 * every Visit::create() failed until the model set $timestamps = false. No
 * test exercised VisitController::store before, which is why the bug shipped
 * live. These assertions all route through the real Visit::create() path.
 */
class VisitControllerTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $clerk;
    private Patient $patient;

    protected function setUp(): void
    {
        parent::setUp();

        $this->hospital = Hospital::factory()->create();
        $this->clerk    = User::factory()->create([
            'hospital_id' => $this->hospital->id,
            'role'        => 'clerk',
        ]);
        $this->patient  = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
    }

    /** A matched verification log for this patient, as a clerk scan would produce. */
    private function matchedLog(): VerificationLog
    {
        return VerificationLog::create([
            'patient_id'  => $this->patient->id,
            'operator_id' => $this->clerk->id,
            'hospital_id' => $this->hospital->id,
            'score'       => 92.0,
            'status'      => 'matched',
            'modality'    => 'hand',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function clerk_can_open_a_visit_and_checkin_completes(): void
    {
        $log = $this->matchedLog();

        $response = $this->actingAs($this->clerk)
            ->postJson('/api/visits', [
                'patient_id'          => $this->patient->id,
                'verification_log_id' => $log->id,
            ])
            ->assertStatus(201)
            ->assertJsonPath('visit.status', 'open')
            ->assertJsonPath('visit.patient_id', $this->patient->id);

        $visitId = $response->json('visit.id');

        $this->assertDatabaseHas('visits', [
            'id'         => $visitId,
            'patient_id' => $this->patient->id,
            'status'     => 'open',
        ]);

        // clerk_checkin is completed immediately using the opening verification.
        $this->assertDatabaseHas('visit_stages', [
            'visit_id'            => $visitId,
            'stage'               => 'clerk_checkin',
            'status'              => 'completed',
            'verification_log_id' => $log->id,
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function opening_a_visit_requires_a_matched_verification(): void
    {
        $log = VerificationLog::create([
            'patient_id'  => $this->patient->id,
            'operator_id' => $this->clerk->id,
            'hospital_id' => $this->hospital->id,
            'score'       => 10.0,
            'status'      => 'no_match',
            'modality'    => 'hand',
        ]);

        $this->actingAs($this->clerk)
            ->postJson('/api/visits', [
                'patient_id'          => $this->patient->id,
                'verification_log_id' => $log->id,
            ])
            ->assertStatus(422);

        $this->assertDatabaseMissing('visits', ['patient_id' => $this->patient->id]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function clerk_can_close_an_open_visit(): void
    {
        $visit = $this->openVisit();
        $log   = $this->matchedLog();

        $this->actingAs($this->clerk)
            ->putJson("/api/visits/{$visit->id}/close", [
                'verification_log_id' => $log->id,
            ])
            ->assertStatus(200)
            ->assertJsonPath('visit.status', 'closed');

        $this->assertDatabaseHas('visits', [
            'id'     => $visit->id,
            'status' => 'closed',
        ]);
        $this->assertDatabaseHas('visit_stages', [
            'visit_id' => $visit->id,
            'stage'    => 'clerk_checkout',
            'status'   => 'completed',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function clerk_can_reopen_a_same_day_closed_visit(): void
    {
        $visit = $this->openVisit();
        $this->actingAs($this->clerk)
            ->putJson("/api/visits/{$visit->id}/close", [
                'verification_log_id' => $this->matchedLog()->id,
            ])
            ->assertStatus(200);

        $this->actingAs($this->clerk)
            ->putJson("/api/visits/{$visit->id}/reopen", [
                'reason' => 'Patient returned — wrong medication dispensed',
            ])
            ->assertStatus(200)
            ->assertJsonPath('visit.status', 'open');

        $this->assertDatabaseHas('visits', [
            'id'           => $visit->id,
            'status'       => 'open',
            'reopen_count' => 1,
        ]);
        // clerk_checkout is reset so it must be re-verified on next close.
        $this->assertDatabaseHas('visit_stages', [
            'visit_id' => $visit->id,
            'stage'    => 'clerk_checkout',
            'status'   => 'pending',
        ]);
    }

    /** Open a visit via the real endpoint and return the fresh model. */
    private function openVisit(): Visit
    {
        $response = $this->actingAs($this->clerk)
            ->postJson('/api/visits', [
                'patient_id'          => $this->patient->id,
                'verification_log_id' => $this->matchedLog()->id,
            ])
            ->assertStatus(201);

        return Visit::findOrFail($response->json('visit.id'));
    }
}
