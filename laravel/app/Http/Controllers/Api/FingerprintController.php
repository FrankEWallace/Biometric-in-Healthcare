<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Services\FingerprintService;
use App\Services\HomisService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FingerprintController extends Controller
{
    /** Minimum Laplacian-variance quality score to accept an enrollment. */
    private const MIN_QUALITY_SCORE = 0.30;

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
                  . 'left_thumb,left_index,left_middle,left_ring,left_little',
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
                  . 'left_thumb,left_index,left_middle,left_ring,left_little',
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

        // ── Load stored template (primary active fingerprint) ─────────────────
        $storedFingerprint = Fingerprint::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->where('is_primary', true)
            ->first();

        if (! $storedFingerprint) {
            // Fall back to any active fingerprint if no primary is set
            $storedFingerprint = Fingerprint::where('patient_id', $patient->id)
                ->where('is_active', true)
                ->first();
        }

        if (! $storedFingerprint) {
            return response()->json([
                'error' => 'No enrolled fingerprint found for this patient.',
            ], 404);
        }

        $storedTemplate = $storedFingerprint->getTemplate();

        if (empty($storedTemplate)) {
            return response()->json([
                'error' => 'Stored fingerprint template is invalid or corrupted.',
            ], 500);
        }

        // ── Process probe image + match against stored template ───────────────
        try {
            $result = $this->fingerprint->verify(
                $request->file('fingerprint')->getRealPath(),
                $storedTemplate,
                $patient->id
            );
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Fingerprint verification failed: ' . $e->getMessage(),
            ], 503);
        }

        // ── GoT-HoMIS enrichment (only on match — failures are non-fatal) ────────
        $ehr       = null;
        $insurance = null;

        if ($result['verdict'] === 'MATCH') {
            $homisId   = (string) $patient->id;
            $ehr       = $this->homis->getPatientRecord($homisId);
            $insurance = $this->homis->getInsuranceEligibility($homisId);
        }

        return response()->json([
            'verdict'         => $result['verdict'],
            'score'           => $result['score'],
            'probe_keypoints' => $result['probe_keypoints'],
            'feature_status'  => $result['feature_status'],
            'patient'         => [
                'id'        => $patient->id,
                'full_name' => $patient->full_name,
            ],
            'matched_finger'  => $storedFingerprint->finger_position,
            'ehr'             => $ehr,
            'insurance'       => $insurance,
        ]);
    }
}
