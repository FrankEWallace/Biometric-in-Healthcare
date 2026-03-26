<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
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
 *   register() → POST /process-fingerprint   multipart image → enhanced features
 *   verify()   → POST /process-fingerprint   probe image → features
 *               POST /match                  probe features + stored template → verdict
 */
class FingerprintService
{
    /** Score threshold for declaring a positive match (0–1 scale). */
    private const MATCH_THRESHOLD = 0.35;

    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.fingerprint.url', 'http://127.0.0.1:5001'), '/');
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
        $response = Http::timeout(15)->post("{$this->baseUrl}/process", [
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
        $response = Http::timeout(30)->post("{$this->baseUrl}/match", [
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

        $response = Http::timeout(20)
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
     * @param  array  $storedTemplate Decrypted template from the Fingerprint model.
     *                                Must contain 'descriptors' key.
     * @param  int    $patientId      ID used as the candidate key in /match.
     * @return array {
     *     verdict: string,           // "MATCH" | "NO MATCH"
     *     score: float,              // 0.0–100.0
     *     raw_score: float,          // 0.0–1.0 (from Python /match)
     *     probe_keypoints: int,
     *     feature_status: string     // "ok" | "low_quality" | "no_features"
     * }
     * @throws RuntimeException  On HTTP errors.
     */
    public function verify(string $filePath, array $storedTemplate, int $patientId): array
    {
        // ── Step 1: extract probe features ───────────────────────────────────
        $probeData = $this->register($filePath);

        $featureStatus = $probeData['features']['status'] ?? 'no_features';
        $probeKeypoints = (int) ($probeData['features']['keypoint_count'] ?? 0);

        // Short-circuit: no features detected in probe image
        if ($featureStatus === 'no_features' || $probeKeypoints === 0) {
            return [
                'verdict'         => 'NO MATCH',
                'score'           => 0.0,
                'raw_score'       => 0.0,
                'probe_keypoints' => $probeKeypoints,
                'feature_status'  => $featureStatus,
            ];
        }

        // ── Step 2: match probe features against stored template ──────────────
        $matchResponse = Http::timeout(30)->post("{$this->baseUrl}/match", [
            'probe'      => $probeData['features'],
            'candidates' => [
                ['patient_id' => $patientId, 'template' => $storedTemplate],
            ],
        ]);

        if ($matchResponse->failed()) {
            $detail = $matchResponse->json('detail') ?? $matchResponse->body();
            throw new RuntimeException("Python /match failed: {$detail}");
        }

        $matchResult = $matchResponse->json();
        $rawScore    = (float) ($matchResult['score'] ?? 0.0);

        return [
            'verdict'         => $rawScore >= self::MATCH_THRESHOLD ? 'MATCH' : 'NO MATCH',
            'score'           => round($rawScore * 100, 2),   // normalise to 0–100
            'raw_score'       => $rawScore,
            'probe_keypoints' => $probeKeypoints,
            'feature_status'  => $featureStatus,
        ];
    }
}
