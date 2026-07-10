<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\SupervisorOverride;
use App\Models\User;
use App\Models\Visit;
use App\Models\VisitStage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Plan 004 — authorization & accountability gaps:
 *   1. supervisor overrides cannot be self-approved
 *   2. stage authorization is deny-by-default (unmapped stage => no role)
 *   3. privileged user/hospital updates are audit-logged
 */
class AccountabilityTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create();
    }

    private function user(string $role): User
    {
        return User::factory()->create([
            'hospital_id' => $this->hospital->id,
            'role'        => $role,
        ]);
    }

    /** A pending override requested by $requester on a fresh pending stage. */
    private function pendingOverride(User $requester): SupervisorOverride
    {
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $visit   = Visit::create([
            'hospital_id' => $this->hospital->id,
            'patient_id'  => $patient->id,
            'opened_by'   => $requester->id,
            'visit_type'  => 'pending',
            'status'      => 'open',
            'opened_at'   => now(),
        ]);
        $stage = VisitStage::create([
            'visit_id' => $visit->id,
            'stage'    => 'triage',
            'status'   => 'pending',
        ]);

        return SupervisorOverride::create([
            'visit_stage_id' => $stage->id,
            'requested_by'   => $requester->id,
            'status'         => 'pending',
            'fallback_chain' => 'fingerprint_and_face_failed',
            'requested_at'   => now(),
        ]);
    }

    // ── 1. Self-approval ────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function a_requester_cannot_resolve_their_own_override(): void
    {
        $nurse    = $this->user('nurse');
        $override = $this->pendingOverride($nurse);

        $this->actingAs($nurse)
            ->putJson("/api/supervisor-overrides/{$override->id}/resolve", [
                'decision' => 'approved',
            ])
            ->assertStatus(403)
            ->assertJsonPath('code', 'self_approval_forbidden');

        $this->assertSame('pending', $override->fresh()->status);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function a_different_supervisor_can_resolve_the_override(): void
    {
        $nurse      = $this->user('nurse');
        $supervisor = $this->user('doctor');
        $override   = $this->pendingOverride($nurse);

        $this->actingAs($supervisor)
            ->putJson("/api/supervisor-overrides/{$override->id}/resolve", [
                'decision' => 'approved',
            ])
            ->assertStatus(200);

        $this->assertSame('approved', $override->fresh()->status);
    }

    // ── 2. Stage deny-by-default ─────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function a_role_not_permitted_at_a_stage_is_denied(): void
    {
        // triage is mapped to ['nurse'] in STAGE_ROLES; a doctor must be denied.
        // (A truly *unmapped* stage name can't be tested end-to-end: the
        // visit_stages.stage column is itself a DB enum, so it stays in sync
        // with STAGE_ROLES — the deny-by-default `=== null` branch guards the
        // code path that would open up only if that invariant ever drifted.)
        $doctor  = $this->user('doctor');
        $patient = Patient::factory()->create(['hospital_id' => $this->hospital->id]);
        $visit   = Visit::create([
            'hospital_id' => $this->hospital->id,
            'patient_id'  => $patient->id,
            'opened_by'   => $doctor->id,
            'visit_type'  => 'pending',
            'status'      => 'open',
            'opened_at'   => now(),
        ]);
        VisitStage::create([
            'visit_id' => $visit->id,
            'stage'    => 'triage',
            'status'   => 'pending',
        ]);

        $this->actingAs($doctor)
            ->postJson("/api/visits/{$visit->id}/stages/triage/verify", [
                'hand_image' => base64_encode('hand'),
                'hand'       => 'right',
            ])
            ->assertStatus(403);
    }

    // ── 3. Audit logging on privileged updates ───────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function updating_a_user_role_is_audit_logged(): void
    {
        $admin  = $this->user('admin');
        $target = $this->user('nurse');

        $before = AuditLog::where('action', AuditLog::ACTION_USER_UPDATED)->count();

        $this->actingAs($admin)
            ->putJson("/api/users/{$target->id}", ['role' => 'doctor'])
            ->assertStatus(200);

        $this->assertSame(
            $before + 1,
            AuditLog::where('action', AuditLog::ACTION_USER_UPDATED)->count(),
        );
        $this->assertDatabaseHas('audit_logs', [
            'action'   => AuditLog::ACTION_USER_UPDATED,
            'staff_id' => $admin->id,
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function updating_a_hospital_perimeter_is_audit_logged(): void
    {
        $admin = $this->user('admin');

        $before = AuditLog::where('action', AuditLog::ACTION_HOSPITAL_UPDATED)->count();

        $this->actingAs($admin)
            ->putJson("/api/hospitals/{$this->hospital->id}", [
                'gps_radius_meters' => 250,
            ])
            ->assertStatus(200);

        $this->assertSame(
            $before + 1,
            AuditLog::where('action', AuditLog::ACTION_HOSPITAL_UPDATED)->count(),
        );
    }
}
