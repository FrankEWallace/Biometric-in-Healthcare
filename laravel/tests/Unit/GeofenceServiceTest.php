<?php

namespace Tests\Unit;

use App\Models\Hospital;
use App\Services\GeofenceService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Unit tests for GeofenceService::isWithinHospital().
 *
 * Failure modes exercised:
 *   - No geofencing configured → always allow (fail-open)
 *   - GPS configured but no coordinates provided → deny
 *   - GPS configured, coordinates within radius → allow
 *   - GPS configured, coordinates outside radius → deny
 *   - WiFi configured, correct SSID → allow
 *   - WiFi configured, wrong SSID → deny
 *   - WiFi configured, no SSID provided → deny
 *   - Both configured: GPS fails → deny regardless of WiFi
 *   - Both configured: WiFi fails → deny regardless of GPS
 *   - Both configured: both pass → allow
 */
class GeofenceServiceTest extends TestCase
{
    use RefreshDatabase;

    private GeofenceService $service;

    // Sarajevo city-centre coordinates used as hospital location in tests
    private const LAT  = 43.8563;
    private const LON  = 18.4131;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = new GeofenceService();
    }

    // ── No restrictions configured ────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function allows_access_when_no_geofencing_is_configured(): void
    {
        $hospital = Hospital::factory()->create([
            'wifi_ssid'    => null,
            'gps_latitude' => null,
            'gps_longitude'=> null,
        ]);

        $this->assertTrue(
            $this->service->isWithinHospital($hospital, null, null, null)
        );
    }

    // ── GPS-only restrictions ─────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_gps_configured_but_coordinates_not_provided(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->create();

        $this->assertFalse(
            $this->service->isWithinHospital($hospital, null, null, null)
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function allows_access_when_device_is_within_gps_radius(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->create();

        // Offset of ~22 m — safely inside 300 m radius
        $this->assertTrue(
            $this->service->isWithinHospital($hospital, self::LAT + 0.0002, self::LON + 0.0002, null)
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_device_is_outside_gps_radius(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->create();

        // Mostar coordinates — ~57 km away
        $this->assertFalse(
            $this->service->isWithinHospital($hospital, 43.3438, 17.8078, null)
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_only_one_coordinate_is_provided(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->create();

        // Latitude provided but longitude is null
        $this->assertFalse(
            $this->service->isWithinHospital($hospital, self::LAT, null, null)
        );
    }

    // ── WiFi-only restrictions ────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function allows_access_when_correct_wifi_ssid_is_provided(): void
    {
        $hospital = Hospital::factory()->withWifi('HOSPITAL-STAFF')->create();

        $this->assertTrue(
            $this->service->isWithinHospital($hospital, null, null, 'HOSPITAL-STAFF')
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_wifi_ssid_does_not_match(): void
    {
        $hospital = Hospital::factory()->withWifi('HOSPITAL-STAFF')->create();

        $this->assertFalse(
            $this->service->isWithinHospital($hospital, null, null, 'PUBLIC-WIFI')
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_wifi_configured_but_no_ssid_provided(): void
    {
        $hospital = Hospital::factory()->withWifi('HOSPITAL-STAFF')->create();

        $this->assertFalse(
            $this->service->isWithinHospital($hospital, null, null, null)
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function wifi_check_is_case_sensitive(): void
    {
        $hospital = Hospital::factory()->withWifi('HOSPITAL-STAFF')->create();

        // Lowercase version must not match
        $this->assertFalse(
            $this->service->isWithinHospital($hospital, null, null, 'hospital-staff')
        );
    }

    // ── Both GPS + WiFi configured ────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_gps_fails_even_if_wifi_matches(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->withWifi('HOSPITAL-STAFF')->create();

        // WiFi correct but far away
        $this->assertFalse(
            $this->service->isWithinHospital($hospital, 43.3438, 17.8078, 'HOSPITAL-STAFF')
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function denies_access_when_wifi_fails_even_if_gps_is_within_radius(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->withWifi('HOSPITAL-STAFF')->create();

        // Within radius but wrong SSID
        $this->assertFalse(
            $this->service->isWithinHospital($hospital, self::LAT + 0.0002, self::LON + 0.0002, 'GUEST-WIFI')
        );
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function allows_access_when_both_gps_and_wifi_conditions_are_met(): void
    {
        $hospital = Hospital::factory()->withGps(self::LAT, self::LON, 300)->withWifi('HOSPITAL-STAFF')->create();

        $this->assertTrue(
            $this->service->isWithinHospital($hospital, self::LAT + 0.0002, self::LON + 0.0002, 'HOSPITAL-STAFF')
        );
    }
}
