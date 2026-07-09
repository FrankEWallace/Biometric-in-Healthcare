<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests for GET /api/matcher-config — read-only snapshot of the matcher
 * operating points, super_admin only.
 */
class MatcherConfigTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_reads_runtime_thresholds(): void
    {
        config([
            'services.fingerprint.match_threshold'             => 32.0,
            'services.fingerprint.contactless_match_threshold' => 57.5,
            'services.geofence.fail_open'                      => false,
        ]);

        $hospital   = Hospital::factory()->create();
        $superAdmin = User::factory()->create([
            'role'        => 'super_admin',
            'hospital_id' => $hospital->id,
        ]);

        $response = $this->actingAs($superAdmin)->getJson('/api/matcher-config');

        $response->assertOk()->assertJson([
            'fingerprint' => [
                'match_threshold'             => 32.0,
                'contactless_match_threshold' => 57.5,
            ],
            'geofence' => ['fail_open' => false],
            'source'   => 'env',
        ]);
        $this->assertIsFloat($response->json('face.match_threshold'));
    }

    public function test_admin_is_forbidden(): void
    {
        $hospital = Hospital::factory()->create();
        $admin    = User::factory()->admin()->create(['hospital_id' => $hospital->id]);

        $this->actingAs($admin)->getJson('/api/matcher-config')->assertForbidden();
    }
}
