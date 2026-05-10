<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\FaceTemplate;
use App\Models\Patient;
use App\Models\VerificationLog;
use App\Services\FaceService;
use App\Services\GeofenceService;
use App\Services\HomisService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FaceController extends Controller
{
    public function __construct(
        private FaceService    $face,
        private GeofenceService $geofence,
        private HomisService   $homis,
    ) {}

    // -------------------------------------------------------------------------
    // POST /api/face/enroll
    // -------------------------------------------------------------------------

    /**
     * Enroll a face template for a patient.
     *
     * Accepts a base64-encoded face image, extracts an embedding via the
     * Python service, and stores the encrypted template in face_templates.
     * Re-enrollment overwrites the existing template (upsert on patient_id).
     *
     * Fields:
     *   image       (string, required) — base64 JPEG or PNG face image
     *   patient_id  (int,    required) — must belong to staff's hospital
     *
     * Requires face_recognition_enabled on the hospital.
     * Roles: nurse, admin.
     */
    public function enroll(Request $request): JsonResponse
    {
        $hospital = $request->user()->hospital;

        if (! $hospital->face_recognition_enabled) {
            return response()->json([
                'error' => 'Facial recognition is not enabled for this hospital.',
            ], 403);
        }

        $data = $request->validate([
            'image'      => 'required|string',
            'patient_id' => 'required|integer|exists:patients,id',
        ]);

        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        try {
            $result = $this->face->process($data['image']);
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Face processing failed: ' . $e->getMessage(),
            ], 422);
        }

        $qualityScore = (float) ($result['quality_score'] ?? 0.0);

        if ($qualityScore < 0.20) {
            return response()->json([
                'error'         => 'Face image quality is too low. Please recapture in better lighting.',
                'quality_score' => $qualityScore,
            ], 422);
        }

        // Upsert — re-enrollment replaces the existing template
        $ft = FaceTemplate::firstOrNew(['patient_id' => $patient->id]);

        $ft->hospital_id   = $patient->hospital_id;
        $ft->enrolled_by   = $request->user()->id;
        $ft->quality_score = $qualityScore;
        $ft->is_active     = true;
        $ft->setTemplate($result['embedding']);
        $ft->save();

        AuditLog::record($request, AuditLog::ACTION_FACE_ENROLL, $patient->id, null, null, [
            'face_template_id' => $ft->id,
            'quality_score'    => $qualityScore,
        ]);

        return response()->json([
            'message'          => 'Face template enrolled successfully.',
            'face_template_id' => $ft->id,
            'patient_id'       => $patient->id,
            'quality_score'    => $qualityScore,
        ], 201);
    }

    // -------------------------------------------------------------------------
    // POST /api/face/verify
    // -------------------------------------------------------------------------

    /**
     * Hospital-wide face identification scan.
     *
     * Extracts an embedding from the probe image, then scores it against every
     * active face template enrolled at the hospital. Returns the best match
     * above MATCH_THRESHOLD, or no_match.
     *
     * Fields:
     *   image          (string,  required)
     *   gps_latitude   (numeric, optional)
     *   gps_longitude  (numeric, optional)
     *   wifi_ssid      (string,  optional)
     *
     * Requires face_recognition_enabled on the hospital.
     * Roles: nurse.
     */
    public function verify(Request $request): JsonResponse
    {
        $operator = $request->user();
        $hospital = $operator->hospital;

        if (! $hospital->face_recognition_enabled) {
            return response()->json([
                'error' => 'Facial recognition is not enabled for this hospital.',
            ], 403);
        }

        $data = $request->validate([
            'image'         => 'required|string',
            'gps_latitude'  => 'nullable|numeric|between:-90,90',
            'gps_longitude' => 'nullable|numeric|between:-180,180',
            'wifi_ssid'     => 'nullable|string|max:100',
        ]);

        // ── Geofence check ────────────────────────────────────────────────────
        if (! $this->geofence->isWithinHospital(
            hospital:  $hospital,
            latitude:  $data['gps_latitude']  ?? null,
            longitude: $data['gps_longitude'] ?? null,
            wifiSsid:  $data['wifi_ssid']     ?? null,
        )) {
            return response()->json([
                'error' => 'Access denied: device is not within hospital premises.',
            ], 403);
        }

        // ── Extract probe embedding ───────────────────────────────────────────
        try {
            $result        = $this->face->process($data['image']);
            $probeEmbedding = $result['embedding'];
        } catch (\RuntimeException $e) {
            $this->writeLog($operator->id, $hospital->id, null, null, 'error', $data, $e->getMessage());
            return response()->json(['error' => 'Face processing failed: ' . $e->getMessage()], 422);
        }

        // ── Load all active face templates for this hospital ──────────────────
        $templates = FaceTemplate::where('hospital_id', $hospital->id)
            ->where('is_active', true)
            ->with('patient:id,full_name,date_of_birth,nida,gender,phone')
            ->get();

        if ($templates->isEmpty()) {
            $this->writeLog($operator->id, $hospital->id, null, 0.0, 'no_match', $data);
            return response()->json([
                'status'  => 'no_match',
                'score'   => 0.0,
                'patient' => null,
            ]);
        }

        // ── Match probe against all candidates ────────────────────────────────
        [$score, $matchedFt] = $this->runMatch($probeEmbedding, $templates);

        $matched        = $score >= FaceService::MATCH_THRESHOLD && $matchedFt !== null;
        $matchedPatient = $matched ? $matchedFt->patient : null;
        $status         = $matched ? 'matched' : 'no_match';

        $log = $this->writeLog(
            operatorId:   $operator->id,
            hospitalId:   $hospital->id,
            patientId:    $matchedPatient?->id,
            score:        $score,
            status:       $status,
            locationData: $data,
        );

        $auditAction = $matched ? AuditLog::ACTION_FACE_MATCH : AuditLog::ACTION_FACE_NO_MATCH;

        AuditLog::record($request, $auditAction, $matchedPatient?->id, null, $status, [
            'score'   => round($score, 4),
            'log_id'  => $log->id,
        ]);

        // ── GoT-HoMIS enrichment on match ─────────────────────────────────────
        $ehr       = null;
        $insurance = null;

        if ($matched && $matchedPatient !== null) {
            $homisId   = (string) $matchedPatient->id;
            $ehr       = $this->homis->getPatientRecord($homisId);
            $insurance = $this->homis->getInsuranceEligibility($homisId);
        }

        return response()->json([
            'status'    => $status,
            'score'     => round($score, 4),
            'patient'   => $matchedPatient,
            'log_id'    => $log->id,
            'ehr'       => $ehr,
            'insurance' => $insurance,
        ]);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private function runMatch(array $probeEmbedding, Collection $templates): array
    {
        $candidates = $templates
            ->map(fn (FaceTemplate $ft) => [
                'patient_id' => $ft->id,
                'embedding'  => $ft->getTemplate()['embedding'] ?? null,
            ])
            ->filter(fn ($c) => $c['embedding'] !== null)
            ->values()
            ->all();

        if (empty($candidates)) {
            return [0.0, null];
        }

        $result    = $this->face->match(['embedding' => $probeEmbedding], $candidates);
        $score     = (float) $result['score'];
        $matchedFt = $templates->firstWhere('id', $result['patient_id']);

        return [$score, $matchedFt];
    }

    private function writeLog(
        int     $operatorId,
        int     $hospitalId,
        ?int    $patientId,
        ?float  $score,
        string  $status,
        array   $locationData = [],
        ?string $errorMessage = null,
    ): VerificationLog {
        return VerificationLog::create([
            'operator_id'   => $operatorId,
            'hospital_id'   => $hospitalId,
            'patient_id'    => $patientId,
            'score'         => $score,
            'status'        => $status,
            'modality'      => 'face',
            'gps_latitude'  => $locationData['gps_latitude']  ?? null,
            'gps_longitude' => $locationData['gps_longitude'] ?? null,
            'wifi_ssid'     => $locationData['wifi_ssid']     ?? null,
            'error_message' => $errorMessage,
        ]);
    }
}
