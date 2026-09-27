<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Restrict access to each hospital's own allowed IP ranges.
 *
 * Ranges are configured per hospital (super_admin, via web admin) in
 * `hospitals.allowed_ip_ranges` — a comma-separated list of CIDR blocks
 * or exact IPs, e.g.:
 *
 *   41.222.10.0/24,196.192.55.10
 *
 * For a cloud-hosted API this should normally be the hospital's public
 * egress/WAN IP (or its range, if static) — not a private RFC1918 range,
 * since that's what the server actually observes once TRUSTED_PROXIES is
 * configured correctly (see plan 003).
 *
 * A hospital with no ranges configured falls back to DEFAULTS (private
 * ranges) — this keeps on-prem/local-network deployments working without
 * per-hospital setup. Users without a hospital (super_admin) are scoped
 * elsewhere and always pass through. Loopback addresses (127.x, ::1) are
 * always allowed so local development and test suites are never blocked.
 */
class CheckHospitalAccess
{
    /** Used when a hospital has not configured allowed_ip_ranges. */
    private const DEFAULTS = [
        '192.168.0.0/16',   // class-C private (covers 192.168.x.x)
        '10.0.0.0/8',       // class-A private
        '172.16.0.0/12',    // class-B private
    ];

    public function handle(Request $request, Closure $next): Response
    {
        $hospital = $request->user()?->hospital;

        // Users without a hospital (super_admin) are scoped elsewhere.
        if ($hospital === null) {
            return $next($request);
        }

        $ip = $request->ip();

        if ($this->isAllowed($ip, $hospital->allowed_ip_ranges)) {
            return $next($request);
        }

        return response()->json([
            'error' => 'Access denied. This endpoint is only available on the hospital network.',
        ], 403);
    }

    // -------------------------------------------------------------------------

    private function isAllowed(string $ip, ?string $configuredRanges): bool
    {
        // Always permit loopback — localhost / artisan commands / tests.
        if ($this->isLoopback($ip)) {
            return true;
        }

        foreach ($this->allowedRanges($configuredRanges) as $range) {
            if ($this->ipInRange($ip, trim($range))) {
                return true;
            }
        }

        return false;
    }

    /** Returns the hospital's configured CIDR list, falling back to DEFAULTS. */
    private function allowedRanges(?string $configuredRanges): array
    {
        if (! empty($configuredRanges)) {
            return array_filter(array_map('trim', explode(',', $configuredRanges)));
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
