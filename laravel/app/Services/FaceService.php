<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * HTTP client for the face recognition endpoints on the Python microservice.
 *
 * Base URL shared with FingerprintService — configured via PYTHON_SERVICE_URL.
 *
 * Endpoints used
 * ──────────────
 *   process()   → POST /face/process      base64 image → ArcFace embedding
 *   identify()  → POST /face/identify     embedding → top-N FAISS candidates
 *   enroll()    → POST /face/enroll       add embedding to FAISS index
 *   remove()    → POST /face/remove       delete patient from FAISS index
 *   rebuild()   → POST /face/rebuild      rebuild FAISS from template list
 *   match()     → POST /face/match        1:1 cosine verification (kept for
 *                                         fingerprint-stage confirmation)
 */
class FaceService
{
    /**
     * Minimum cosine similarity to include a patient in the face shortlist.
     * Calibrate using FAR/FRR measurements on your deployment hardware.
     */
    public const IDENTIFY_THRESHOLD = 0.40;

    /**
     * Minimum cosine similarity to confirm a 1:1 face match.
     */
    public const MATCH_THRESHOLD = 0.75;

    /**
     * Maximum active face templates stored per patient.
     * Enforced in FaceController before calling enroll().
     */
    public const MAX_TEMPLATES_PER_PATIENT = 5;

    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.fingerprint.url', 'http://127.0.0.1:5001'), '/');
    }

    // ── Core biometric operations ─────────────────────────────────────────────

    /**
     * Send a base64 face image to /face/process and return the ArcFace embedding.
     *
     * @param  string $base64Image  Base64-encoded JPEG or PNG.
     * @return array  { embedding: float[], quality_score: float, face_detected: bool, bbox: float[]|null }
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
     * Search the FAISS index for the top matching patients.
     *
     * The returned candidates are sorted by cosine similarity (descending).
     * Filter by IDENTIFY_THRESHOLD before trusting any candidate.
     *
     * @param  array $embedding  512-dim ArcFace vector.
     * @param  int   $topK       Number of candidates to return (default 5).
     * @return array  { candidates: [{ patient_id: int, template_id: int, score: float }] }
     * @throws RuntimeException
     */
    public function identify(array $embedding, int $topK = 5): array
    {
        $response = Http::timeout(15)->post("{$this->baseUrl}/face/identify", [
            'embedding' => $embedding,
            'top_k'     => $topK,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/identify failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();
    }

    /**
     * Register one face embedding in the FAISS index.
     *
     * Must be called after the FaceTemplate row is persisted so that
     * template_id is available.
     *
     * @param  int   $patientId
     * @param  int   $templateId  face_templates.id
     * @param  array $embedding   512-dim float vector.
     * @throws RuntimeException
     */
    public function enrollToIndex(int $patientId, int $templateId, array $embedding): void
    {
        $response = Http::timeout(15)->post("{$this->baseUrl}/face/enroll", [
            'patient_id'  => $patientId,
            'template_id' => $templateId,
            'embedding'   => $embedding,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/enroll failed: ' . ($response->json('detail') ?? $response->body())
            );
        }
    }

    /**
     * Remove all embeddings for a patient from the FAISS index.
     *
     * Call when deactivating or deleting all of a patient's face templates.
     *
     * @param  int $patientId
     * @throws RuntimeException
     */
    public function removeFromIndex(int $patientId): void
    {
        $response = Http::timeout(10)->post("{$this->baseUrl}/face/remove", [
            'patient_id' => $patientId,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/remove failed: ' . ($response->json('detail') ?? $response->body())
            );
        }
    }

    /**
     * Rebuild the entire FAISS index from a list of decrypted templates.
     *
     * Each item must have [patient_id, template_id, embedding].
     * Call after bulk migrations or when the on-disk index is lost.
     *
     * @param  array $templates
     * @return int   Number of vectors indexed.
     * @throws RuntimeException
     */
    public function rebuildIndex(array $templates): int
    {
        $response = Http::timeout(120)->post("{$this->baseUrl}/face/rebuild", [
            'templates' => $templates,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/rebuild failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return (int) ($response->json('indexed_count') ?? 0);
    }

    // ── Passive liveness check ────────────────────────────────────────────────

    /**
     * Send a base64 face image to /face/liveness and return the liveness verdict.
     *
     * @param  string $base64Image  Base64-encoded JPEG or PNG.
     * @return array  { is_live: bool, screen_score: float, highlight_ratio: float, reason: string }
     * @throws RuntimeException
     */
    public function liveness(string $base64Image): array
    {
        $response = Http::timeout(15)->post("{$this->baseUrl}/face/liveness", [
            'image' => $base64Image,
        ]);

        if ($response->failed()) {
            throw new RuntimeException(
                'Python /face/liveness failed: ' . ($response->json('detail') ?? $response->body())
            );
        }

        return $response->json();
    }

    // ── Legacy 1:1 match (kept for fingerprint-stage confirmation) ────────────

    /**
     * Score a probe embedding against an explicit candidate list.
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
