<?php

namespace App\Http\Middleware;

use App\Services\GeofenceService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Server-side on-premises gate for biometric enrollment endpoints.
 *
 * Verification endpoints run the same check inside their controllers
 * (they also write a verification log on denial); enrollment endpoints
 * use this middleware so a stolen staff token cannot enroll biometrics
 * from outside the hospital.
 *
 * GPS coordinates and WiFi SSID are read from the request body. They are
 * client-reported and therefore spoofable — this is defence in depth on
 * top of device attestation, not a substitute for it.
 */
class EnforceGeofence
{
    public function __construct(private GeofenceService $geofence) {}

    public function handle(Request $request, Closure $next): Response
    {
        $hospital = $request->user()?->hospital;

        // Users without a hospital (super_admin) are scoped elsewhere;
        // hospital.access middleware governs what they may touch.
        if ($hospital === null) {
            return $next($request);
        }

        $lat  = $request->input('gps_latitude');
        $lon  = $request->input('gps_longitude');
        $ssid = $request->input('wifi_ssid');

        $within = $this->geofence->isWithinHospital(
            $hospital,
            is_numeric($lat) ? (float) $lat : null,
            is_numeric($lon) ? (float) $lon : null,
            is_string($ssid) && $ssid !== '' ? $ssid : null,
        );

        if (! $within) {
            return response()->json([
                'error' => 'Access denied: device is not within hospital premises.',
                'code'  => 'geofence_denied',
            ], 403);
        }

        return $next($request);
    }
}
