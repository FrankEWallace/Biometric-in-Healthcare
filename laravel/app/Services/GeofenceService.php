<?php

namespace App\Services;

use App\Models\Hospital;

/**
 * Validates that a verification attempt originates from within
 * hospital premises using two independent signals:
 *   1. GPS distance from the hospital's registered coordinates
 *   2. WiFi SSID match
 *
 * Both signals are optional — if the hospital has not configured a
 * value, that check is skipped. If neither is configured, access is
 * allowed (fail-open per policy decision; tighten in production).
 */
class GeofenceService
{
    public function isWithinHospital(
        Hospital $hospital,
        ?float   $latitude,
        ?float   $longitude,
        ?string  $wifiSsid,
    ): bool {
        $gpsConfigured  = $hospital->gps_latitude !== null && $hospital->gps_longitude !== null;
        $wifiConfigured = $hospital->wifi_ssid !== null;

        // No restrictions configured — allow
        if (! $gpsConfigured && ! $wifiConfigured) {
            return true;
        }

        $gpsOk  = ! $gpsConfigured || $this->isWithinRadius($hospital, $latitude, $longitude);
        $wifiOk = ! $wifiConfigured || ($wifiSsid && $wifiSsid === $hospital->wifi_ssid);

        // Both configured checks must pass
        return $gpsOk && $wifiOk;
    }

    // ------------------------------------------------------------------
    // Haversine formula — returns true if the device is within the
    // hospital's allowed radius (in metres).
    // ------------------------------------------------------------------

    private function isWithinRadius(Hospital $hospital, ?float $lat, ?float $lon): bool
    {
        if ($lat === null || $lon === null) {
            return false;
        }

        $earthRadius = 6371000; // metres

        $dLat = deg2rad($lat - $hospital->gps_latitude);
        $dLon = deg2rad($lon - $hospital->gps_longitude);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($hospital->gps_latitude))
            * cos(deg2rad($lat))
            * sin($dLon / 2) ** 2;

        $distance = 2 * $earthRadius * asin(sqrt($a));

        return $distance <= $hospital->gps_radius_meters;
    }
}
