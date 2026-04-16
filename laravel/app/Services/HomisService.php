<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Client for the Government of Tanzania Health Operations Management
 * Information System (GoT-HoMIS).
 *
 * Covers two modules:
 *   - Patient Registration  → getPatientRecord()
 *   - Insurance Management  → getInsuranceEligibility()
 *
 * Both methods retry up to HOMIS_RETRIES times with exponential back-off
 * and return null gracefully when GoT-HoMIS is unreachable, so a network
 * outage never blocks a successful fingerprint match.
 */
class HomisService
{
    private string $baseUrl;
    private string $apiKey;
    private int    $timeout;
    private int    $maxRetries;

    public function __construct()
    {
        $this->baseUrl    = rtrim(config('services.homis.url', ''), '/');
        $this->apiKey     = config('services.homis.key', '');
        $this->timeout    = config('services.homis.timeout', 10);
        $this->maxRetries = config('services.homis.retries', 3);
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Fetch a patient's Electronic Health Record from the Patient
     * Registration module.
     *
     * Returns null when GoT-HoMIS is unreachable or returns an error,
     * so the verification flow can still succeed without EHR data.
     */
    public function getPatientRecord(string $patientId): ?array
    {
        return $this->get("/patients/{$patientId}", 'patient_registration');
    }

    /**
     * Check NHIF/CHF insurance eligibility from the Insurance Management
     * module.
     *
     * Returns null on failure — callers should treat null as "eligibility
     * unknown" rather than "not eligible".
     */
    public function getInsuranceEligibility(string $patientId): ?array
    {
        return $this->get("/insurance/eligibility/{$patientId}", 'insurance');
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Execute a GET request against GoT-HoMIS with exponential back-off retry.
     *
     * Retry only on connection/timeout errors and 5xx responses.
     * 4xx (bad request / not found) are not retried — they are permanent.
     */
    private function get(string $path, string $module): ?array
    {
        if (empty($this->baseUrl)) {
            // GoT-HoMIS not configured — skip silently (e.g. local dev)
            return null;
        }

        $url     = $this->baseUrl . $path;
        $attempt = 0;

        while ($attempt < $this->maxRetries) {
            $attempt++;

            try {
                $response = Http::withHeaders([
                    'Authorization' => 'Bearer ' . $this->apiKey,
                    'Accept'        => 'application/json',
                    'X-Module'      => $module,
                ])
                ->timeout($this->timeout)
                ->get($url);

                if ($response->successful()) {
                    return $response->json();
                }

                // 4xx — do not retry; log and return null
                if ($response->clientError()) {
                    Log::warning('HomisService: client error', [
                        'module'  => $module,
                        'url'     => $url,
                        'status'  => $response->status(),
                    ]);
                    return null;
                }

                // 5xx — retry after back-off
                Log::warning("HomisService: server error (attempt {$attempt})", [
                    'module' => $module,
                    'status' => $response->status(),
                ]);

            } catch (ConnectionException $e) {
                Log::warning("HomisService: connection error (attempt {$attempt})", [
                    'module'  => $module,
                    'message' => $e->getMessage(),
                ]);
            } catch (RequestException $e) {
                Log::warning("HomisService: request exception (attempt {$attempt})", [
                    'module'  => $module,
                    'message' => $e->getMessage(),
                ]);
            }

            if ($attempt < $this->maxRetries) {
                // Exponential back-off: 500ms, 1000ms, 2000ms …
                usleep((int) (500_000 * 2 ** ($attempt - 1)));
            }
        }

        Log::error("HomisService: all {$this->maxRetries} attempts failed", [
            'module' => $module,
            'url'    => $url,
        ]);

        return null;
    }
}
