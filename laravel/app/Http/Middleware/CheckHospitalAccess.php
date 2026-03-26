<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Restrict access to hospital-network IP ranges only.
 *
 * Allowed ranges are configured via HOSPITAL_IP_RANGES in .env as a
 * comma-separated list of CIDR blocks or exact IPs, e.g.:
 *
 *   HOSPITAL_IP_RANGES=192.168.1.0/24,10.0.0.0/8
 *
 * Falls back to the default ranges defined in DEFAULTS below when the
 * env variable is absent.  Loopback addresses (127.x, ::1) are always
 * allowed so local development and test suites are never blocked.
 */
class CheckHospitalAccess
{
    /** Used when HOSPITAL_IP_RANGES is not set in .env */
    private const DEFAULTS = [
        '192.168.0.0/16',   // class-C private (covers 192.168.x.x)
        '10.0.0.0/8',       // class-A private
        '172.16.0.0/12',    // class-B private
    ];

    public function handle(Request $request, Closure $next): Response
    {
        $ip = $request->ip();

        if ($this->isAllowed($ip)) {
            return $next($request);
        }

        return response()->json([
            'error' => 'Access denied. This endpoint is only available on the hospital network.',
        ], 403);
    }

    // -------------------------------------------------------------------------

    private function isAllowed(string $ip): bool
    {
        // Always permit loopback — localhost / artisan commands / tests.
        if ($this->isLoopback($ip)) {
            return true;
        }

        foreach ($this->allowedRanges() as $range) {
            if ($this->ipInRange($ip, trim($range))) {
                return true;
            }
        }

        return false;
    }

    /** Returns the configured CIDR list, falling back to DEFAULTS. */
    private function allowedRanges(): array
    {
        $env = config('hospital.ip_ranges')
            ?? env('HOSPITAL_IP_RANGES');

        if (! empty($env)) {
            return array_filter(array_map('trim', explode(',', $env)));
        }

        return self::DEFAULTS;
    }

    /** True for 127.x.x.x and ::1 (IPv4-mapped ::ffff:127.x too). */
    private function isLoopback(string $ip): bool
    {
        return $ip === '127.0.0.1'
            || $ip === '::1'
            || str_starts_with($ip, '127.')
            || str_starts_with($ip, '::ffff:127.');
    }

    /**
     * Check whether an IP falls inside a CIDR range or exactly matches it.
     *
     * Accepts:
     *   - CIDR notation: "192.168.1.0/24"
     *   - Exact IP:      "192.168.1.100"
     */
    private function ipInRange(string $ip, string $range): bool
    {
        if (! str_contains($range, '/')) {
            // Exact match.
            return $ip === $range;
        }

        [$subnet, $bits] = explode('/', $range, 2);

        if (! filter_var($subnet, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)
            || ! ctype_digit($bits)
            || (int) $bits < 0
            || (int) $bits > 32
        ) {
            return false;
        }

        $mask       = $bits === '0' ? 0 : (~0 << (32 - (int) $bits));
        $subnetLong = ip2long($subnet);
        $ipLong     = ip2long($ip);

        if ($subnetLong === false || $ipLong === false) {
            return false;
        }

        return ($ipLong & $mask) === ($subnetLong & $mask);
    }
}
