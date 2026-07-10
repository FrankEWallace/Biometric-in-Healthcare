<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Services\PatientAccessService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The shared access-control seam (plan 005). Identity is resolved nationally;
 * this service decides record access. Today: same-hospital only.
 */
class PatientAccessServiceTest extends TestCase
{
    use RefreshDatabase;

    private PatientAccessService $access;

    protected function setUp(): void
    {
        parent::setUp();
        $this->access = new PatientAccessService();
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function access_is_allowed_within_the_same_hospital(): void
    {
        $hospital = Hospital::factory()->create();
        $operator = User::factory()->create(['hospital_id' => $hospital->id]);
        $patient  = Patient::factory()->create(['hospital_id' => $hospital->id]);

        $this->assertTrue($this->access->authorizePatientAccess($operator, $patient));
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function access_is_denied_across_hospitals(): void
    {
        $hospitalA = Hospital::factory()->create();
        $hospitalB = Hospital::factory()->create();
        $operator  = User::factory()->create(['hospital_id' => $hospitalA->id]);
        $patient   = Patient::factory()->create(['hospital_id' => $hospitalB->id]);

        $this->assertFalse($this->access->authorizePatientAccess($operator, $patient));
    }
}
