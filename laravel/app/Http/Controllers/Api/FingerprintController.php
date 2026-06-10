<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Models\VerificationLog;
use App\Services\FingerprintService;
use App\Services\HomisService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class FingerprintController extends Controller
{
    /** Minimum quality score for phone camera hand captures (Laplacian/300). */
    private const MIN_QUALITY_SCORE = 0.10;

    /** Target number of captures per finger for a full gallery. */
    private const GALLERY_SIZE = 3;

    /**
     * Single-use liveness tokens issued by livenessCheck() and consumed by
     * enrollGallery(). The token — not a client-asserted boolean — is the
     * proof that this user's capture session passed the server-side
     * optical-flow check within the TTL.
     */
    private const LIVENESS_TOKEN_PREFIX      = 'fp_liveness_token:';
    private const LIVENESS_TOKEN_TTL_MINUTES = 10;

    public function __construct(
        private FingerprintService $fingerprint,
        private HomisService       $homis,
    ) {}

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/upload   (legacy — kept for backward compatibility)
    // -------------------------------------------------------------------------

    /**
     * Accepts a multipart image file from the mobile app, converts it to
     * base64, runs it through the Python /process endpoint (legacy ORB
     * pipeline), and stores the resulting template linked to the given patient.
     *
     * Fields:
     *   fingerprint      (file, required)  – JPEG/PNG image
     *   patient_id       (int,  required)  – must belong to staff's hospital
     *   finger_position  (str,  optional)  – defaults to right_index
     *   is_primary       (bool, optional)  – defaults to false
     */
    public function upload(Request $request): JsonResponse
    {
        $data = $request->validate([
            'fingerprint' => 'required|file|mimes:jpeg,jpg,png|max:5120',
            'patient_id'  => 'required|integer|exists:patients,id',
            'finger_position' => [
                'nullable',
                'in:right_thumb,right_index,right_middle,right_ring,right_little,'
                  . 'left_thumb,left_index,left_middle,left_ring,left_little,'
                  . 'right_hand,left_hand',
            ],
            'is_primary' => 'nullable|boolean',
        ]);

        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        $base64 = base64_encode(
            file_get_contents($request->file('fingerprint')->getRealPath())
        );

        try {
            $result = $this->fingerprint->process($base64);
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Fingerprint processing failed: ' . $e->getMessage(),
            ], 503);
        }

        $qualityScore = (float) ($result['quality_score'] ?? 0.0);

        if ($qualityScore < self::MIN_QUALITY_SCORE) {
            return response()->json([
                'error'         => 'Fingerprint quality is too low. Please recapture.',
                'quality_score' => $qualityScore,
                'minimum'       => self::MIN_QUALITY_SCORE,
            ], 422);
        }

        $fingerPosition = $data['finger_position'] ?? 'right_index';
        $isPrimary      = (bool) ($data['is_primary'] ?? false);

        if ($isPrimary) {
            Fingerprint::where('patient_id', $patient->id)
                ->where('is_primary', true)
                ->update(['is_primary' => false]);
        }

        $fp = Fingerprint::firstOrNew([
            'patient_id'      => $patient->id,
            'finger_position' => $fingerPosition,
        ]);

        $fp->hospital_id   = $patient->hospital_id;
        $fp->enrolled_by   = $request->user()->id;
        $fp->quality_score = $qualityScore;
        $fp->is_primary    = $isPrimary;
        $fp->is_active     = true;
        $fp->setTemplate($result['template']);
        $fp->save();

        return response()->json([
            'message'         => 'Fingerprint uploaded successfully.',
            'fingerprint_id'  => $fp->id,
            'patient_id'      => $patient->id,
            'finger_position' => $fp->finger_position,
            'quality_score'   => $fp->quality_score,
            'is_primary'      => $fp->is_primary,
        ], 201);
    }

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/register
    // -------------------------------------------------------------------------

    /**
     * Enroll a fingerprint using the enhanced preprocessing pipeline.
     *
     * Sends the uploaded image to Python /process-fingerprint (full pipeline:
     * grayscale → blur → histogram equalization → adaptive threshold →
     * morphological thinning → ORB feature extraction), then stores the
     * resulting feature template in the fingerprints table.
     *
     * Fields:
     *   fingerprint      (file, required)  – JPEG/PNG image, max 5 MB
     *   patient_id       (int,  required)  – must belong to staff's hospital
     *   finger_position  (str,  optional)  – defaults to right_index
     *   is_primary       (bool, optional)  – defaults to false
     *
     * Responses:
     *   201  – enrollment successful
     *   404  – patient not in staff's hospital
     *   422  – quality too low or feature extraction failed
     *   503  – Python service unavailable
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'fingerprint' => 'required|file|mimes:jpeg,jpg,png|max:5120',
            'patient_id'  => 'required|integer|exists:patients,id',
            'finger_position' => [
                'nullable',
                'in:right_thumb,right_index,right_middle,right_ring,right_little,'
                  . 'left_thumb,left_index,left_middle,left_ring,left_little,'
                  . 'right_hand,left_hand',
            ],
            'is_primary' => 'nullable|boolean',
        ]);

        // ── Scope check ───────────────────────────────────────────────────────
        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        // ── Send to Python enhanced pipeline ──────────────────────────────────
        try {
            $result = $this->fingerprint->register(
                $request->file('fingerprint')->getRealPath()
            );
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Fingerprint processing failed: ' . $e->getMessage(),
            ], 503);
        }

        // ── Quality gate ─────────────────────────────────────────────────────
        $qualityScore  = (float) ($result['quality_score'] ?? 0.0);
        $featureStatus = $result['features']['status'] ?? 'no_features';

        if ($qualityScore < self::MIN_QUALITY_SCORE) {
            return response()->json([
                'error'         => 'Fingerprint quality is too low. Please recapture.',
                'quality_score' => $qualityScore,
                'minimum'       => self::MIN_QUALITY_SCORE,
            ], 422);
        }

        if ($featureStatus === 'no_features') {
            return response()->json([
                'error'          => 'No fingerprint features could be extracted. Please recapture.',
                'feature_status' => $featureStatus,
            ], 422);
        }

        $fingerPosition = $data['finger_position'] ?? 'right_index';
        $isPrimary      = (bool) ($data['is_primary'] ?? false);

        // ── Demote existing primary if needed ─────────────────────────────────
        if ($isPrimary) {
            Fingerprint::where('patient_id', $patient->id)
                ->where('is_primary', true)
                ->update(['is_primary' => false]);
        }

        // ── Upsert — re-enrolling same finger replaces old template ───────────
        $fp = Fingerprint::firstOrNew([
            'patient_id'      => $patient->id,
            'finger_position' => $fingerPosition,
        ]);

        $fp->hospital_id   = $patient->hospital_id;
        $fp->enrolled_by   = $request->user()->id;
        $fp->quality_score = $qualityScore;
        $fp->is_primary    = $isPrimary;
        $fp->is_active     = true;
        $fp->setTemplate($result['features']);  // store ORB features as template
        $fp->save();

        return response()->json([
            'message'         => 'Fingerprint registered successfully.',
            'fingerprint_id'  => $fp->id,
            'patient_id'      => $patient->id,
            'finger_position' => $fp->finger_position,
            'quality_score'   => $fp->quality_score,
            'keypoint_count'  => $result['features']['keypoint_count'] ?? 0,
            'feature_status'  => $featureStatus,
            'steps_applied'   => $result['steps_applied'] ?? [],
            'is_primary'      => $fp->is_primary,
        ], 201);
    }

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/enroll-gallery
    // -------------------------------------------------------------------------

    /**
     * Enroll a "gallery" of up to 3 captures for a single finger in one request.
     *
     * The mobile app auto-triggers 3 captures of the same finger in one session
     * (different angles / ridge coverage) and runs liveness ONCE for the session.
     * This endpoint processes each capture, keeps the usable ones, stores them as
     * a gallery, and atomically flags the highest-quality capture as the gallery
     * lead — the single template used for 1:N identification. 1:1 verification
     * matches a probe against the whole gallery (Max-Rule).
     *
     * Floor of 1: as long as one capture is usable the patient is enrolled; if
     * fewer than 3 land, the gallery is flagged needs_reenrollment. If NONE are
     * usable, returns 422 (code: no_usable_capture) so the client can fall back
     * to face enrollment.
     *
     * Decisions: .claude/grill-sessions/2026-06-05-multi-capture-fingerprint-enrollment.md
     *
     * Fields:
     *   patient_id       (int,    required)  – must belong to staff's hospital
     *   captures[]       (file[], required, 1–3) – JPEG/PNG, max 5 MB each
     *   finger_position  (str,    optional)  – defaults to right_index
     *   is_primary       (bool,   optional)  – marks this finger as the 1:N primary
     *   liveness_token   (str,    required)  – single-use token issued by
     *                                          /fingerprint/liveness-check on a pass
     *
     * Responses:
     *   201  – gallery enrolled (see gallery_size / needs_reenrollment)
     *   404  – patient not in staff's hospital
     *   422  – liveness token missing/expired/reused, or no usable capture
     *   503  – Python service unavailable
     */
    public function enrollGallery(Request $request): JsonResponse
    {
        $data = $request->validate([
            'patient_id'      => 'required|integer|exists:patients,id',
            'finger_position' => [
                'nullable',
                'in:right_thumb,right_index,right_middle,right_ring,right_little,'
                  . 'left_thumb,left_index,left_middle,left_ring,left_little,'
                  . 'right_hand,left_hand',
            ],
            'is_primary'      => 'nullable|boolean',
            'liveness_token'  => 'required|string',
            'captures'        => 'required|array|min:1|max:' . self::GALLERY_SIZE,
            'captures.*'      => 'required|file|mimes:jpeg,jpg,png|max:5120',
        ]);

        // ── Scope check ───────────────────────────────────────────────────────
        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        // ── Session liveness gate ─────────────────────────────────────────────
        // The token is minted by /fingerprint/liveness-check only when the
        // server-side optical-flow check passed. Pull = single use; it must
        // belong to the same staff user and be inside its TTL.
        $tokenOwner = Cache::pull(self::LIVENESS_TOKEN_PREFIX . $data['liveness_token']);

        if ($tokenOwner !== $request->user()->id) {
            return response()->json([
                'error' => 'Liveness check did not pass for this capture session. Please recapture.',
                'code'  => 'liveness_required',
            ], 422);
        }

        // ── Process every capture, keep only usable templates ─────────────────
        $accepted = [];   // [['quality' => float, 'features' => array, 'keypoints' => int], ...]
        $rejected = [];   // [['index' => int, 'reason' => str, ...], ...]

        foreach (array_values($request->file('captures')) as $i => $file) {
            try {
                $result = $this->fingerprint->register($file->getRealPath());
            } catch (\RuntimeException $e) {
                $rejected[] = ['index' => $i, 'reason' => 'processing_failed', 'detail' => $e->getMessage()];
                continue;
            }

            $quality = (float) ($result['quality_score'] ?? 0.0);
            $status  = $result['features']['status'] ?? 'no_features';

            if ($status === 'no_features') {
                $rejected[] = ['index' => $i, 'reason' => 'no_features', 'quality_score' => $quality];
                continue;
            }
            if ($quality < self::MIN_QUALITY_SCORE) {
                $rejected[] = ['index' => $i, 'reason' => 'low_quality', 'quality_score' => $quality];
                continue;
            }

            $accepted[] = [
                'quality'   => $quality,
                'features'  => $result['features'],
                'keypoints' => $result['features']['keypoint_count'] ?? 0,
            ];
        }

        // ── Floor of 1: at least one usable capture is required ───────────────
        if (empty($accepted)) {
            return response()->json([
                'error'    => 'No usable fingerprint could be captured. Fall back to face enrollment.',
                'code'     => 'no_usable_capture',
                'rejected' => $rejected,
            ], 422);
        }

        $fingerPosition = $data['finger_position'] ?? 'right_index';
        $isPrimary      = (bool) ($data['is_primary'] ?? false);

        // Degraded coverage when fewer than a full gallery's worth landed.
        $needsReenrollment = count($accepted) < self::GALLERY_SIZE;

        // Lead = highest-quality accepted capture (the 1:N representative).
        $leadIndex = 0;
        foreach ($accepted as $idx => $cap) {
            if ($cap['quality'] > $accepted[$leadIndex]['quality']) {
                $leadIndex = $idx;
            }
        }

        // ── Persist the gallery atomically ────────────────────────────────────
        $created = DB::transaction(function () use (
            $patient, $request, $fingerPosition, $isPrimary,
            $accepted, $leadIndex, $needsReenrollment
        ) {
            // Re-enrolling a finger replaces its previous gallery entirely.
            Fingerprint::where('patient_id', $patient->id)
                ->where('finger_position', $fingerPosition)
                ->delete();

            // Only the lead of the primary finger carries is_primary, so the 1:N
            // primary pass stays one-template-per-finger. Demote any prior primary.
            if ($isPrimary) {
                Fingerprint::where('patient_id', $patient->id)
                    ->where('is_primary', true)
                    ->update(['is_primary' => false]);
            }

            $rows = [];
            foreach ($accepted as $idx => $cap) {
                $isLead = $idx === $leadIndex;

                $fp = new Fingerprint([
                    'patient_id'         => $patient->id,
                    'hospital_id'        => $patient->hospital_id,
                    'enrolled_by'        => $request->user()->id,
                    'finger_position'    => $fingerPosition,
                    'quality_score'      => $cap['quality'],
                    'is_primary'         => $isPrimary && $isLead,
                    'is_gallery_lead'    => $isLead,
                    'needs_reenrollment' => $needsReenrollment,
                    'is_active'          => true,
                ]);
                $fp->setTemplate($cap['features']);
                $fp->save();

                $rows[] = $fp;
            }

            return $rows;
        });

        $lead = collect($created)->firstWhere('is_gallery_lead', true);

        return response()->json([
            'message'             => 'Fingerprint gallery enrolled successfully.',
            'patient_id'          => $patient->id,
            'finger_position'     => $fingerPosition,
            'gallery_size'        => count($created),
            'requested'           => count($request->file('captures')),
            'lead_fingerprint_id' => $lead?->id,
            'lead_quality_score'  => $lead?->quality_score,
            'is_primary'          => $isPrimary,
            'needs_reenrollment'  => $needsReenrollment,
            'rejected'            => $rejected,
        ], 201);
    }

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/verify
    // -------------------------------------------------------------------------

    /**
     * Directly verify a fingerprint image against a specific patient's
     * stored template.
     *
     * Use this endpoint when you already know which patient to check
     * (e.g., the patient hands over their ID card). For hospital-wide
     * identification (no known patient), use POST /api/verify instead.
     *
     * Pipeline:
     *   1. Load the patient's primary active fingerprint template from DB.
     *   2. Process the probe image via Python /process-fingerprint.
     *   3. Match probe features against the stored template via Python /match.
     *   4. Return verdict + normalised score.
     *
     * Fields:
     *   fingerprint  (file, required)  – probe JPEG/PNG image, max 5 MB
     *   patient_id   (int,  required)  – patient to verify against
     *
     * Responses:
     *   200  – verification completed (check 'verdict' field for result)
     *   404  – patient not found / no enrolled fingerprint
     *   503  – Python service unavailable
     */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'fingerprint' => 'required|file|mimes:jpeg,jpg,png|max:5120',
            'patient_id'  => 'required|integer|exists:patients,id',
        ]);

        // ── Scope check ───────────────────────────────────────────────────────
        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        // ── Load ALL active fingerprints for the patient ──────────────────────
        $enrolledFingerprints = Fingerprint::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->get();

        if ($enrolledFingerprints->isEmpty()) {
            return response()->json([
                'error' => 'No enrolled fingerprint found for this patient.',
            ], 404);
        }

        // Build candidate list, skipping locked or templateless records
        $candidates      = [];
        $fingerprintMap  = [];   // fingerprint_id → model instance

        foreach ($enrolledFingerprints as $fp) {
            if ($fp->isLocked()) {
                continue;
            }
            $template = $fp->getTemplate();
            if (empty($template)) {
                continue;
            }
            $candidates[]              = ['fingerprint_id' => $fp->id, 'template' => $template];
            $fingerprintMap[$fp->id]   = $fp;
        }

        if (empty($candidates)) {
            // All fingerprints are either locked or corrupted
            return response()->json([
                'error'     => 'All fingerprint records for this patient are locked or invalid. Contact an administrator.',
                'locked_at' => $enrolledFingerprints->first()?->locked_at,
            ], 423);
        }

        // ── Match probe against every enrolled template ───────────────────────
        try {
            $result = $this->fingerprint->verifyAgainstAll(
                $request->file('fingerprint')->getRealPath(),
                $candidates
            );
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Fingerprint verification failed: ' . $e->getMessage(),
            ], 503);
        }

        // Resolve which Fingerprint model was the best match
        $matchedFpId       = $result['matched_fingerprint_id'];
        $storedFingerprint = $fingerprintMap[$matchedFpId] ?? $enrolledFingerprints->first();

        // ── Track failures and lock if threshold reached ──────────────────────
        if ($result['verdict'] !== 'MATCH') {
            $justLocked = $storedFingerprint->recordFailure();

            if ($justLocked) {
                AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_LOCK, $patient->id, null, null, [
                    'fingerprint_id'  => $storedFingerprint->id,
                    'failed_attempts' => $storedFingerprint->failed_attempts,
                    'window_hours'    => \App\Models\Fingerprint::LOCK_WINDOW_HOURS,
                ]);

                return response()->json([
                    'verdict' => 'NO_MATCH',
                    'error'   => 'Fingerprint locked after ' . \App\Models\Fingerprint::LOCK_THRESHOLD
                                 . ' failed attempts within 1 hour. Contact an administrator.',
                ], 423);
            }

            AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_NO_MATCH, $patient->id, null, null, [
                'fingerprint_id'  => $storedFingerprint->id,
                'failed_attempts' => $storedFingerprint->failed_attempts,
            ]);
        } else {
            // Successful match — reset failure counters on the matched finger
            $storedFingerprint->unlock();
        }

        // ── GoT-HoMIS enrichment (only on match — failures are non-fatal) ─────
        $ehr       = null;
        $insurance = null;

        if ($result['verdict'] === 'MATCH') {
            $homisId   = (string) $patient->id;
            $ehr       = $this->homis->getPatientRecord($homisId);
            $insurance = $this->homis->getInsuranceEligibility($homisId);
        }

        // Create a VerificationLog so the result can be linked to a visit stage
        $log = VerificationLog::create([
            'patient_id'    => $result['verdict'] === 'MATCH' ? $patient->id : null,
            'fingerprint_id' => $result['verdict'] === 'MATCH' ? $storedFingerprint->id : null,
            'operator_id'   => $request->user()->id,
            'hospital_id'   => $request->user()->hospital_id,
            'score'         => $result['score'],
            'status'        => $result['verdict'] === 'MATCH' ? 'matched' : 'no_match',
            'modality'      => 'fingerprint',
            'gps_latitude'  => $request->input('gps_latitude'),
            'gps_longitude' => $request->input('gps_longitude'),
            'wifi_ssid'     => $request->input('wifi_ssid'),
        ]);

        return response()->json([
            'verdict'              => $result['verdict'],
            'score'                => $result['score'],
            'threshold'            => $result['threshold'],
            'probe_minutiae'       => $result['probe_minutiae'],
            'probe_keypoints'      => $result['probe_keypoints'],
            'feature_status'       => $result['feature_status'],
            'enrolled_count'       => count($candidates),
            'verification_log_id'  => $log->id,
            'patient'              => [
                'id'        => $patient->id,
                'full_name' => $patient->full_name,
            ],
            'matched_finger'  => $storedFingerprint->finger_position,
            'ehr'             => $ehr,
            'insurance'       => $insurance,
        ]);
    }

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/liveness-check
    // -------------------------------------------------------------------------

    /**
     * Optical-flow passive liveness check on a sequence of fingerprint frames.
     *
     * The mobile app captures several frames in quick succession before the
     * final still photograph.  A live finger shows micro-movement from
     * breathing / pulse (mean displacement 0.15–2.5 px).  A printed image or
     * phone screen shows near-zero displacement.
     *
     * This endpoint does not touch patient data — no hospital-scope check
     * is needed beyond the authenticated session.
     *
     * Fields:
     *   frames[]  (string[], required, min:2, max:12) — base64-encoded JPEG/PNG
     *             frames ordered from oldest to newest.
     *
     * Responses:
     *   200  — verdict returned (check 'is_live' field)
     *   422  — validation error (too few frames, empty strings)
     *   503  — Python service unavailable
     */
    public function livenessCheck(Request $request): JsonResponse
    {
        $data = $request->validate([
            'frames'   => 'required|array|min:2|max:12',
            'frames.*' => 'required|string|min:1',
        ]);

        try {
            $result = $this->fingerprint->livenessCheck($data['frames']);
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Liveness check failed: ' . $e->getMessage(),
            ], 503);
        }

        // A passing check earns a single-use token that enroll-gallery requires.
        // The verdict therefore never travels through the client as a boolean.
        if ($result['is_live'] ?? false) {
            $token = Str::random(48);
            Cache::put(
                self::LIVENESS_TOKEN_PREFIX . $token,
                $request->user()->id,
                now()->addMinutes(self::LIVENESS_TOKEN_TTL_MINUTES),
            );
            $result['liveness_token'] = $token;
        }

        return response()->json($result);
    }

    // -------------------------------------------------------------------------
    // POST /api/fingerprint/{fingerprint}/unlock   (admin / super_admin only)
    // -------------------------------------------------------------------------

    /**
     * Unlock a locked fingerprint record and reset its failure counters.
     * The fingerprint must belong to the admin's hospital (super_admin is unrestricted).
     */
    public function unlock(Request $request, Fingerprint $fingerprint): JsonResponse
    {
        $this->authorize('unlock', $fingerprint);

        if (! $fingerprint->isLocked()) {
            return response()->json(['error' => 'Fingerprint is not locked.'], 409);
        }

        $fingerprint->unlock();

        AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_UNLOCK, $fingerprint->patient_id, null, null, [
            'fingerprint_id'  => $fingerprint->id,
            'finger_position' => $fingerprint->finger_position,
        ]);

        return response()->json([
            'message'        => 'Fingerprint unlocked successfully.',
            'fingerprint_id' => $fingerprint->id,
            'patient_id'     => $fingerprint->patient_id,
        ]);
    }
}
