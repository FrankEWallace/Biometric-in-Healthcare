<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Thin HTTP client that talks to the Python OpenCV microservice.
 * Base URL is configured via PYTHON_SERVICE_URL in .env
 * (default: http://127.0.0.1:5001).
 */
class FingerprintService
{
    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.fingerprint.url', 'http://127.0.0.1:5001'), '/');
    }

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
                'Python /process failed: ' . ($response->json('error') ?? $response->body())
            );
        }

        return $response->json('template');
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
                'Python /match failed: ' . ($response->json('error') ?? $response->body())
            );
        }

        return $response->json(); // { patient_id, score }
    }
}
