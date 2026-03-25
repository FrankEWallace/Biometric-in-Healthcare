<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Services\FingerprintService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FingerprintController extends Controller
{
    private const MIN_QUALITY_SCORE = 0.30;

    public function __construct(private FingerprintService $fingerprint) {}

    /**
     * POST /api/fingerprint/upload
     *
     * Accepts a multipart image file from the mobile app, converts it to
     * base64, runs it through the Python processing service, and stores the
     * resulting template linked to the given patient.
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

        // ------------------------------------------------------------------
        // 1. Scope-check — patient must belong to the staff member's hospital
        // ------------------------------------------------------------------
        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        // ------------------------------------------------------------------
        // 2. Convert uploaded file to base64 for Python service
        // ------------------------------------------------------------------
        $base64 = base64_encode(
            file_get_contents($request->file('fingerprint')->getRealPath())
        );

        // ------------------------------------------------------------------
        // 3. Extract template + quality score via Python service
        // ------------------------------------------------------------------
        try {
            $result = $this->fingerprint->process($base64);
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Fingerprint processing failed: ' . $e->getMessage(),
            ], 503);
        }

        $qualityScore = (float) ($result['quality_score'] ?? 0.0);

        // ------------------------------------------------------------------
        // 4. Quality gate
        // ------------------------------------------------------------------
        if ($qualityScore < self::MIN_QUALITY_SCORE) {
            return response()->json([
                'error'         => 'Fingerprint quality is too low. Please recapture.',
                'quality_score' => $qualityScore,
                'minimum'       => self::MIN_QUALITY_SCORE,
            ], 422);
        }

        $fingerPosition = $data['finger_position'] ?? 'right_index';
        $isPrimary      = (bool) ($data['is_primary'] ?? false);

        // ------------------------------------------------------------------
        // 5. Demote existing primary fingerprint for this patient if needed
        // ------------------------------------------------------------------
        if ($isPrimary) {
            Fingerprint::where('patient_id', $patient->id)
                ->where('is_primary', true)
                ->update(['is_primary' => false]);
        }

        // ------------------------------------------------------------------
        // 6. Upsert — re-enrolling the same finger replaces the old template
        // ------------------------------------------------------------------
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
}
