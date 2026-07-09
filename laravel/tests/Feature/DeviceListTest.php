<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Hospital;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests for GET /api/devices — read-only device inventory derived from
 * audit logs, grouped by (ip_address, user_agent).
 */
class DeviceListTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospitalA;
    private Hospital $hospitalB;
    private User $adminA;
    private User $superAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->hospitalA  = Hospital::factory()->create();
        $this->hospitalB  = Hospital::factory()->create();
        $this->adminA     = User::factory()->admin()->create(['hospital_id' => $this->hospitalA->id]);
        $this->superAdmin = User::factory()->create([
            'role'        => 'super_admin',
            'hospital_id' => $this->hospitalA->id,
        ]);
    }

    private function makeLog(User $staff, string $ip, string $agent, string $action = 'login_success'): AuditLog
    {
        return AuditLog::create([
            'staff_id'    => $staff->id,
            'hospital_id' => $staff->hospital_id,
            'action'      => $action,
            'ip_address'  => $ip,
            'user_agent'  => $agent,
        ]);
    }

    public function test_admin_sees_only_own_hospital_devices(): void
    {
        $adminB = User::factory()->admin()->create(['hospital_id' => $this->hospitalB->id]);

        $this->makeLog($this->adminA, '10.0.0.5', 'Dalvik/2.1 (Android 13)');
        $this->makeLog($adminB, '10.0.0.9', 'Dalvik/2.1 (Android 14)');

        $response = $this->actingAs($this->adminA)->getJson('/api/devices');

        $response->assertOk()->assertJsonCount(1, 'devices');
        $this->assertSame('10.0.0.5', $response->json('devices.0.ip_address'));
    }

    public function test_super_admin_sees_all_and_can_filter_by_hospital(): void
    {
        $adminB = User::factory()->admin()->create(['hospital_id' => $this->hospitalB->id]);

        $this->makeLog($this->adminA, '10.0.0.5', 'Dalvik/2.1 (Android 13)');
        $this->makeLog($adminB, '10.0.0.9', 'Dalvik/2.1 (Android 14)');

        $all = $this->actingAs($this->superAdmin)->getJson('/api/devices');
        $all->assertOk()->assertJsonCount(2, 'devices');

        $filtered = $this->actingAs($this->superAdmin)
            ->getJson('/api/devices?hospital_id=' . $this->hospitalB->id);
        $filtered->assertOk()->assertJsonCount(1, 'devices');
        $this->assertSame('10.0.0.9', $filtered->json('devices.0.ip_address'));
    }

    public function test_devices_are_grouped_with_counts_and_last_actor(): void
    {
        $nurse = User::factory()->nurse()->create(['hospital_id' => $this->hospitalA->id]);

        $this->makeLog($this->adminA, '10.0.0.5', 'Dalvik/2.1 (Android 13)');
        $this->makeLog($nurse, '10.0.0.5', 'Dalvik/2.1 (Android 13)', 'fingerprint_match');
        $this->makeLog($nurse, '10.0.0.7', 'Mozilla/5.0');

        $response = $this->actingAs($this->adminA)->getJson('/api/devices');

        $response->assertOk()->assertJsonCount(2, 'devices');

        $grouped = collect($response->json('devices'))
            ->firstWhere('ip_address', '10.0.0.5');

        $this->assertSame(2, $grouped['request_count']);
        // Newest row in the group wins: the nurse's fingerprint_match
        $this->assertSame($nurse->id, $grouped['last_staff']['id']);
        $this->assertSame('fingerprint_match', $grouped['last_action']);
    }

    public function test_nurse_is_forbidden(): void
    {
        $nurse = User::factory()->nurse()->create(['hospital_id' => $this->hospitalA->id]);

        $this->actingAs($nurse)->getJson('/api/devices')->assertForbidden();
    }
}
