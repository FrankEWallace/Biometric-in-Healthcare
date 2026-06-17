<?php

namespace App\Services;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * HTTP client that talks to the Python OpenCV microservice.
 *
 * Base URL is configured via PYTHON_SERVICE_URL in .env
 * (default: http://127.0.0.1:5001).
 *
 * Methods
 * ───────
 *  Legacy (used by VerificationController — hospital-wide search)
 *   process()  → POST /process    base64 JSON → ORB template
 *   match()    → POST /match      probe template + candidates → best patient_id
 *
 *  New (used by FingerprintController — register + direct verify)
 *   register()      → POST /process-fingerprint   multipart image → enhanced features
 *   verify()        → POST /process-fingerprint   probe image → features
 *                     POST /match                  probe features + stored template → verdict
 *   livenessCheck() → POST /fingerprint/liveness-check   frame list → optical-flow verdict
 */
class FingerprintService
{
    /**
     * Minimum minutiae match score to declare a positive match.
     * Scale: 0–100 (2 × matched_pairs / total_minutiae × 100).
     *
     * Single source of truth: services.fingerprint.match_threshold
     * (FINGERPRINT_MATCH_THRESHOLD in .env, default 32.0). Calibrate with
     * tools/calibrate_far_frr.py and keep the Python service's env var in sync.
     */
    private string $baseUrl;

    private float $matchThreshold;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.fingerprint.url', 'http://127.0.0.1:5001'), '/');
        $this->matchThreshold = (float) config('services.fingerprint.match_threshold', 32.0);
    }

    /**
     * Pending request carrying the internal API key the Python service
     * requires (X-Internal-Api-Key, matching its INTERNAL_API_KEY env).
     */
    private function http(int $timeout): PendingRequest
    {
        $request = Http::timeout($timeout);

        if ($key = config('services.fingerprint.key')) {
            $request = $request->withHeaders(['X-Internal-Api-Key' => $key]);
        }

        return $request;
    }

    // -------------------------------------------------------------------------
    // Legacy methods (keep for VerificationController compatibility)
    // -------------------------------------------------------------------------

    /**
     * Send a base64 image to /process and return the ORB template array.
     *
     * @param  string $base64Image
     * @return array  ['keypoints' => [...], 'descriptors' => [...]]
     * @throws RuntimeException
     */
    public function process(string $base64Image): array
    {
        $response = $this->http(15)->post("{$this->baseUrl}/process", [
            'image' => $base64Image,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /process failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();   // { template: {...}, quality_score: float }
    }

    /**
     * Send a probe template + candidate list to /match.
     *
     * @param  array $probe      ORB template array
     * @param  array $candidates [['patient_id' => int, 'template' => array], ...]
     * @return array ['patient_id' => int, 'score' => float]
     * @throws RuntimeException
     */
    public function match(array $probe, array $candidates): array
    {
        $response = $this->http(30)->post("{$this->baseUrl}/match", [
            'probe'      => $probe,
            'candidates' => $candidates,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /match failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();   // { patient_id: int, score: float }
    }

    // -------------------------------------------------------------------------
    // New methods — enhanced preprocessing pipeline
    // -------------------------------------------------------------------------

    /**
     * Send a fingerprint image file to /process-fingerprint.
     *
     * Runs the full enhanced pipeline on the Python side:
     *   grayscale → Gaussian blur → histogram equalization
     *   → adaptive threshold → morphological thinning → ORB feature extraction
     *
     * @param  string $filePath  Absolute path to the uploaded JPEG/PNG file.
     * @return array {
     *     success: bool,
     *     quality_score: float,          // Laplacian-variance score [0, 1]
     *     steps_applied: string[],
     *     processed_image: string,       // base64 PNG of the skeleton
     *     features: {
     *         keypoint_count: int,
     *         status: string,            // "ok" | "low_quality" | "no_features"
     *         keypoints: array,
     *         descriptors: array         // (N×32) uint8 nested list
     *     }
     * }
     * @throws RuntimeException  On HTTP error or Python-side processing failure.
     */
    public function register(string $filePath): array
    {
        $fileName = basename($filePath);
        $mimeType = mime_content_type($filePath) ?: 'image/jpeg';

        $response = $this->http(20)
            ->attach('file', file_get_contents($filePath), $fileName, ['Content-Type' => $mimeType])
            ->post("{$this->baseUrl}/process-fingerprint");

        if ($response->failed()) {
            $detail = $response->json('detail') ?? $response->body();
            throw new RuntimeException("Python /process-fingerprint failed: {$detail}");
        }

        $data = $response->json();

        if (empty($data['success'])) {
            throw new RuntimeException(
                'Python /process-fingerprint returned an unsuccessful response.'
            );
        }

        return $data;
    }

    /**
     * Verify a new fingerprint image against a single stored template.
     *
     * Two-step process:
     *   1. POST new image to /process-fingerprint → extract probe features.
     *   2. POST probe features + stored template to /match → compare.
     *
     * Returns a normalised result with a 0–100 score and a plain-English
     * verdict so the controller does not need to know matching thresholds.
     *
     * @param  string $filePath       Absolute path to the probe JPEG/PNG.
     * @param  array  $storedTemplate Decrypted SourceAFIS template from the Fingerprint model.
     * @param  int    $patientId      ID used as the candidate key in /match.
     * @return array {
     *     verdict: string,           // "MATCH" | "NO MATCH"
     *     score: float,              // SourceAFIS raw score (0–∞, threshold 40)
     *     probe_minutiae: int,
     *     feature_status: string     // "ok" | "low_quality" | "no_features"
     * }
     * @throws RuntimeException  On HTTP errors.
     */
    /**
     * Verify a probe image against ALL enrolled fingerprints for a patient.
     *
     * Processes the probe image once, then sends every active template as a
     * candidate to Python /match in a single HTTP call.  The Python service
     * returns the best-scoring candidate (fingerprint_id used as the key).
     * A MATCH is declared if that best score meets MATCH_THRESHOLD.
     *
     * @param  string $filePath    Absolute path to the probe JPEG/PNG.
     * @param  array  $candidates  [['fingerprint_id' => int, 'template' => array], ...]
     * @return array {
     *     verdict: string,              // "MATCH" | "NO MATCH"
     *     score: float,
     *     threshold: float,
     *     matched_fingerprint_id: int,  // ID of the best-matching Fingerprint row
     *     probe_minutiae: int,
     *     probe_keypoints: int,
     *     feature_status: string
     * }
     */
    public function verifyAgainstAll(string $filePath, array $candidates): array
    {
        // ── Step 1: extract probe template ───────────────────────────────────
        $probeData = $this->register($filePath);

        $featureStatus = $probeData['features']['status'] ?? 'no_features';
        $probeMinutiae = (int) ($probeData['features']['minutiae_count'] ?? 0);

        if ($featureStatus === 'no_features' || $probeMinutiae === 0) {
            return [
                'verdict'               => 'NO MATCH',
                'score'                 => 0.0,
                'threshold'             => $this->matchThreshold,
                'matched_fingerprint_id'=> 0,
                'probe_minutiae'        => $probeMinutiae,
                'probe_keypoints'       => $probeMinutiae,
                'feature_status'        => $featureStatus,
            ];
        }

        // ── Step 2: match probe against all candidates in one call ────────────
        // Re-key candidates so patient_id in the Python response maps back to
        // the fingerprint row ID (all candidates share the same real patient).
        $pythonCandidates = array_map(fn ($c) => [
            'patient_id' => $c['fingerprint_id'],
            'template'   => $c['template'],
        ], $candidates);

        $matchResponse = $this->http(30)->post("{$this->baseUrl}/match", [
            'probe'      => $probeData['features'],
            'candidates' => $pythonCandidates,
        ]);

        if ($matchResponse->failed()) {
            throw new RuntimeException(
                'Python /match failed: ' . ($matchResponse->json('detail') ?? $matchResponse->body())
            );
        }

        $matchResult          = $matchResponse->json();
        $score                = (float) ($matchResult['score'] ?? 0.0);
        $matchedFingerprintId = (int)   ($matchResult['patient_id'] ?? 0);

        Log::debug('FingerprintService::verifyAgainstAll', [
            'candidate_count'       => count($candidates),
            'probe_minutiae'        => $probeMinutiae,
            'score'                 => $score,
            'matched_fingerprint_id'=> $matchedFingerprintId,
            'threshold'             => $this->matchThreshold,
            'verdict'               => $score >= $this->matchThreshold ? 'MATCH' : 'NO MATCH',
        ]);

        return [
            'verdict'               => $score >= $this->matchThreshold ? 'MATCH' : 'NO MATCH',
            'score'                 => round($score, 2),
            'threshold'             => $this->matchThreshold,
            'matched_fingerprint_id'=> $matchedFingerprintId,
            'probe_minutiae'        => $probeMinutiae,
            'probe_keypoints'       => $probeMinutiae,
            'feature_status'        => $featureStatus,
        ];
    }

    // -------------------------------------------------------------------------
    // Fingerprint passive liveness check
    // -------------------------------------------------------------------------

    /**
     * Send a sequence of base64-encoded frames to the Python optical-flow
     * liveness endpoint and return the verdict.
     *
     * @param  string[] $base64Frames  Ordered list (oldest → newest), min 2.
     * @return array {
     *     is_live:           bool,
     *     mean_displacement: float,  // average px displacement per frame pair
     *     frame_count:       int,
     *     reason:            string  // "ok" | "static_image" | "insufficient_frames" | "no_features"
     * }
     * @throws RuntimeException  On HTTP error or Python-side failure.
     */
    public function livenessCheck(array $base64Frames): array
    {
        $response = $this->http(30)->post("{$this->baseUrl}/fingerprint/liveness-check", [
            'frames' => $base64Frames,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /fingerprint/liveness-check failed: '
                . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();
    }
}
