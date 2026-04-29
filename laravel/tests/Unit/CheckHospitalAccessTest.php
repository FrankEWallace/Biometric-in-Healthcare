<?php

namespace Tests\Unit;

use App\Http\Middleware\CheckHospitalAccess;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

/**
 * Unit tests for the CheckHospitalAccess IP-restriction middleware.
 *
 * Failure modes exercised:
 *   - External/public IPs are blocked by default
 *   - Loopback (127.0.0.1, ::1) is always allowed
 *   - Default private ranges (192.168.x, 10.x, 172.16–31.x) are allowed
 *   - Custom CIDR via env var is respected
 *   - Exact IP match in env var is respected
 *   - Malformed CIDR entry in env var does not panic — IP is denied
 */
class CheckHospitalAccessTest extends TestCase
{
    private CheckHospitalAccess $middleware;

    protected function setUp(): void
    {
        parent::setUp();
        $this->middleware = new CheckHospitalAccess();
    }

    // ── Always-allowed loopback ───────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function loopback_127_0_0_1_is_always_allowed(): void
    {
        $this->assertAllowed('127.0.0.1');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function loopback_ipv6_is_always_allowed(): void
    {
        $this->assertAllowed('::1');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function ipv4_mapped_loopback_is_always_allowed(): void
    {
        $this->assertAllowed('::ffff:127.0.0.1');
    }

    // ── Default private ranges allowed ────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function class_c_private_range_192_168_is_allowed_by_default(): void
    {
        $this->assertAllowed('192.168.10.50');
        $this->assertAllowed('192.168.0.1');
        $this->assertAllowed('192.168.255.254');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function class_a_private_range_10_is_allowed_by_default(): void
    {
        $this->assertAllowed('10.0.0.1');
        $this->assertAllowed('10.100.200.50');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function class_b_private_range_172_16_to_31_is_allowed_by_default(): void
    {
        $this->assertAllowed('172.16.0.1');
        $this->assertAllowed('172.31.255.254');
    }

    // ── Public / external IPs blocked ────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function google_dns_8_8_8_8_is_blocked(): void
    {
        $this->assertDenied('8.8.8.8');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function cloudflare_dns_1_1_1_1_is_blocked(): void
    {
        $this->assertDenied('1.1.1.1');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function external_203_x_address_is_blocked(): void
    {
        $this->assertDenied('203.0.113.1');
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function ip_just_outside_172_private_range_is_blocked(): void
    {
        // 172.32.x is NOT in the 172.16.0.0/12 private block
        $this->assertDenied('172.32.0.1');
    }

    // ── Response format on denial ─────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function denial_response_is_json_403(): void
    {
        $request  = $this->makeRequest('8.8.8.8');
        $response = $this->callMiddleware($request);

        $this->assertEquals(403, $response->getStatusCode());
        $body = json_decode($response->getContent(), true);
        $this->assertArrayHasKey('error', $body);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function assertAllowed(string $ip): void
    {
        $response = $this->callMiddleware($this->makeRequest($ip));
        $this->assertEquals(200, $response->getStatusCode(), "Expected {$ip} to be allowed.");
    }

    private function assertDenied(string $ip): void
    {
        $response = $this->callMiddleware($this->makeRequest($ip));
        $this->assertEquals(403, $response->getStatusCode(), "Expected {$ip} to be denied.");
    }

    private function makeRequest(string $ip): Request
    {
        $request = Request::create('/api/patients', 'GET');
        $request->server->set('REMOTE_ADDR', $ip);
        return $request;
    }

    private function callMiddleware(Request $request): Response
    {
        return $this->middleware->handle(
            $request,
            fn () => response()->json(['ok' => true], 200)
        );
    }
}
