<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * HTTP client for the face recognition endpoints on the Python microservice.
 *
 * Base URL shared with FingerprintService — configured via PYTHON_SERVICE_URL.
 *
 * Endpoints
 * ─────────
 *   process() → POST /face/process   base64 image → face embedding + quality score
 *   match()   → POST /face/match     probe embedding + candidates → best patient_id + score
 */
class FaceService
{
    /** Cosine similarity threshold for a positive face match. */
    public const MATCH_THRESHOLD = 0.75;

    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.fingerprint.url', 'http://127.0.0.1:5001'), '/');
    }

    /**
     * Send a base64 face image to /face/process.
     *
     * @param  string $base64Image  Base64-encoded JPEG or PNG.
     * @return array  { embedding: float[], quality_score: float, face_detected: bool }
     * @throws RuntimeException
     */
    public function process(string $base64Image): array
    {
        $response = Http::timeout(15)->post("{$this->baseUrl}/face/process", [
            'image' => $base64Image,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/process failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        $data = $response->json();

        if (! ($data['face_detected'] ?? false)) {
            throw new RuntimeException('No face detected in the image. Please recapture.');
        }

        return $data;
    }

    /**
     * Send a probe embedding + candidate list to /face/match.
     *
     * @param  array $probe       { embedding: float[] }
     * @param  array $candidates  [['patient_id' => int, 'embedding' => float[]], ...]
     * @return array { patient_id: int, score: float }
     * @throws RuntimeException
     */
    public function match(array $probe, array $candidates): array
    {
        $response = Http::timeout(30)->post("{$this->baseUrl}/face/match", [
            'probe'      => $probe,
            'candidates' => $candidates,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/match failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();
    }
}
