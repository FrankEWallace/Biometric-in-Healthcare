<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Regression coverage for plan 003: Laravel must trust the X-Forwarded-For
 * chain ONLY from the configured reverse proxy (TRUSTED_PROXIES), never from
 * '*'. Otherwise a client on the public internet could forge a private-range
 * X-Forwarded-For to satisfy the CheckHospitalAccess IP gate and spoof the
 * audit-log source IP.
 *
 * The test suite runs with the default TRUSTED_PROXIES=172.16.0.0/12, and
 * CheckHospitalAccess allows the private hospital ranges (192.168/16, 10/8,
 * 172.16/12) plus loopback.
 */
class ForwardedIpTrustTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $hospital   = Hospital::factory()->create();
        $this->user = User::factory()->create([
            'hospital_id' => $hospital->id,
            'role'        => 'nurse',
        ]);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function a_forged_forwarded_ip_from_an_untrusted_client_is_ignored(): void
    {
        // The connecting client is a public IP (not loopback, not a hospital
        // range, and NOT in the trusted-proxy range), but forges an
        // X-Forwarded-For claiming to be inside the hospital network.
        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.10']);

        $this->actingAs($this->user)
            ->withHeaders(['X-Forwarded-For' => '192.168.1.50'])
            ->getJson('/api/visits')
            // Because 203.0.113.10 is not a trusted proxy, the forged header is
            // dropped, $request->ip() stays 203.0.113.10, and the gate denies.
            ->assertStatus(403);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function legitimate_traffic_through_the_trusted_proxy_still_passes(): void
    {
        // The request genuinely arrives from the trusted reverse-proxy subnet
        // (172.16.0.0/12) — real internal traffic must not be broken by the fix.
        $this->withServerVariables(['REMOTE_ADDR' => '172.16.0.5']);

        $this->actingAs($this->user)
            ->withHeaders(['X-Forwarded-For' => '192.168.1.50'])
            ->getJson('/api/visits')
            ->assertStatus(200);
    }
}
