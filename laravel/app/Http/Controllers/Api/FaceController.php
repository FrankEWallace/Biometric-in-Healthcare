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
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class FaceController extends Controller
{
    public function __construct(
        private FaceService     $face,
        private GeofenceService $geofence,
        private HomisService    $homis,
    ) {}

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/face/enroll
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Enroll a face template for a patient (multi-sample support).
     *
     * Each call stores one new FaceTemplate row and registers the embedding
     * in the FAISS index.  Up to FaceService::MAX_TEMPLATES_PER_PATIENT active
     * templates are allowed; the oldest is deactivated when the cap is reached.
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

        // ── Extract ArcFace embedding ─────────────────────────────────────────
        try {
            $result = $this->face->process($data['image']);
        } catch (\RuntimeException $e) {
            return response()->json([
                'error' => 'Face processing failed: ' . $e->getMessage(),
            ], 422);
        }

        $qualityScore = (float) ($result['quality_score'] ?? 0.0);

        if ($qualityScore < 0.50) {
            return response()->json([
                'error'         => 'Face image quality is too low. Please recapture in better lighting.',
                'quality_score' => $qualityScore,
            ], 422);
        }

        // ── Passive liveness check ────────────────────────────────────────────
        try {
            $liveness = $this->face->liveness($data['image']);
        } catch (\RuntimeException $e) {
            return response()->json(['error' => 'Liveness check failed: ' . $e->getMessage()], 503);
        }

        if (! ($liveness['is_live'] ?? false)) {
            return response()->json([
                'error'  => 'Liveness check failed — possible spoofing attempt. Please retake using a real face.',
                'reason' => $liveness['reason'] ?? 'unknown',
            ], 422);
        }

        // ── Enforce per-patient template cap ──────────────────────────────────
        $activeTemplates = FaceTemplate::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->orderBy('created_at')
            ->get();

        DB::transaction(function () use ($patient, $request, $result, $qualityScore, $activeTemplates) {
            // Deactivate the oldest template when at cap
            if ($activeTemplates->count() >= FaceService::MAX_TEMPLATES_PER_PATIENT) {
                $oldest = $activeTemplates->first();
                $oldest->update(['is_active' => false]);
                $this->face->removeFromIndex($patient->id);

                // Re-enroll remaining active templates so FAISS stays consistent
                $activeTemplates->skip(1)->each(function (FaceTemplate $ft) use ($patient) {
                    $decoded = $ft->getTemplate();
                    if ($decoded && isset($decoded['embedding'])) {
                        $this->face->enrollToIndex($patient->id, $ft->id, $decoded['embedding']);
                    }
                });
            }

            // Create new template row
            $ft = new FaceTemplate();
            $ft->patient_id   = $patient->id;
            $ft->hospital_id  = $patient->hospital_id;
            $ft->enrolled_by  = $request->user()->id;
            $ft->quality_score = $qualityScore;
            $ft->is_active    = true;
            $ft->setTemplate($result['embedding']);
            $ft->save();

            // Register in FAISS index
            $this->face->enrollToIndex($patient->id, $ft->id, $result['embedding']);

            AuditLog::record($request, AuditLog::ACTION_FACE_ENROLL, $patient->id, null, null, [
                'face_template_id' => $ft->id,
                'quality_score'    => $qualityScore,
                'template_count'   => $activeTemplates->count() + 1,
            ]);
        });

        $ft = FaceTemplate::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->latest()
            ->first();

        return response()->json([
            'message'          => 'Face template enrolled successfully.',
            'face_template_id' => $ft->id,
            'patient_id'       => $patient->id,
            'quality_score'    => $qualityScore,
            'active_templates' => FaceTemplate::where('patient_id', $patient->id)
                ->where('is_active', true)->count(),
        ], 201);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/face/verify
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Hospital-wide face identification using FAISS.
     *
     * Extracts an ArcFace embedding from the probe image, searches the
     * FAISS index for the top candidates, then returns the best match above
     * IDENTIFY_THRESHOLD along with patient details and EHR data.
     *
     * Decision states returned in 'status':
     *   matched        — single confident match above threshold
     *   no_match       — no candidate above threshold
     *   needs_review   — top candidate score is borderline; staff should verify
     *   error          — embedding extraction failed
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

        // ── Passive liveness check ────────────────────────────────────────────
        try {
            $liveness = $this->face->liveness($data['image']);
        } catch (\RuntimeException $e) {
            return response()->json(['error' => 'Liveness check failed: ' . $e->getMessage()], 503);
        }

        if (! ($liveness['is_live'] ?? false)) {
            return response()->json([
                'error'  => 'Liveness check failed — possible spoofing attempt. Please retake using a real face.',
                'reason' => $liveness['reason'] ?? 'unknown',
            ], 422);
        }

        // ── Extract probe embedding ───────────────────────────────────────────
        try {
            $processed      = $this->face->process($data['image']);
            $probeEmbedding = $processed['embedding'];
        } catch (\RuntimeException $e) {
            $this->writeLog($operator->id, $hospital->id, null, null, 'error', $data, $e->getMessage());
            return response()->json(['error' => 'Face processing failed: ' . $e->getMessage()], 422);
        }

        // ── FAISS identification ───────────────────────────────────────────────
        try {
            $faissResult = $this->face->identify($probeEmbedding, topK: 5);
            $candidates  = $faissResult['candidates'] ?? [];
        } catch (\RuntimeException $e) {
            $this->writeLog($operator->id, $hospital->id, null, null, 'error', $data, $e->getMessage());
            return response()->json(['error' => 'Identification failed: ' . $e->getMessage()], 500);
        }

        if (empty($candidates)) {
            $log = $this->writeLog($operator->id, $hospital->id, null, 0.0, 'no_match', $data);
            return response()->json(['status' => 'no_match', 'score' => 0.0, 'patient' => null, 'log_id' => $log->id]);
        }

        // ── Interpret top candidate ───────────────────────────────────────────
        $top   = $candidates[0];
        $score = (float) $top['score'];

        [$status, $patient] = $this->interpretCandidate($top, $hospital->id, $score);

        $log = $this->writeLog(
            operatorId:   $operator->id,
            hospitalId:   $hospital->id,
            patientId:    $patient?->id,
            score:        $score,
            status:       $status,
            locationData: $data,
        );

        $auditAction = ($status === 'matched')
            ? AuditLog::ACTION_FACE_MATCH
            : AuditLog::ACTION_FACE_NO_MATCH;

        AuditLog::record($request, $auditAction, $patient?->id, null, $status, [
            'score'  => round($score, 4),
            'log_id' => $log->id,
        ]);

        // ── EHR enrichment on confirmed match ─────────────────────────────────
        $ehr = $insurance = null;

        if ($status === 'matched' && $patient !== null) {
            $homisId   = (string) $patient->id;
            $ehr       = $this->homis->getPatientRecord($homisId);
            $insurance = $this->homis->getInsuranceEligibility($homisId);
        }

        return response()->json([
            'status'    => $status,
            'score'     => round($score, 4),
            'patient'   => $patient,
            'log_id'    => $log->id,
            'ehr'       => $ehr,
            'insurance' => $insurance,
        ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/face/rebuild-index  (admin only)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Rebuild the FAISS index from all active face templates in the database.
     *
     * Use after server restarts where the on-disk index was lost, or after
     * bulk patient imports.  Expensive — only admins should trigger this.
     */
    public function rebuildIndex(Request $request): JsonResponse
    {
        $hospital = $request->user()->hospital;

        $templates = FaceTemplate::where('hospital_id', $hospital->id)
            ->where('is_active', true)
            ->get()
            ->map(function (FaceTemplate $ft) {
                $decoded = $ft->getTemplate();
                if (! $decoded || empty($decoded['embedding'])) {
                    return null;
                }
                return [
                    'patient_id'  => $ft->patient_id,
                    'template_id' => $ft->id,
                    'embedding'   => $decoded['embedding'],
                ];
            })
            ->filter()
            ->values()
            ->all();

        try {
            $count = $this->face->rebuildIndex($templates);
        } catch (\RuntimeException $e) {
            return response()->json(['error' => 'Index rebuild failed: ' . $e->getMessage()], 500);
        }

        return response()->json([
            'message'       => 'FAISS index rebuilt successfully.',
            'indexed_count' => $count,
        ]);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Classify the top FAISS candidate into a decision status.
     *
     * Returns [status, patient|null].
     * Status values: 'matched', 'needs_review', 'no_match'
     */
    private function interpretCandidate(array $candidate, int $hospitalId, float $score): array
    {
        $threshold       = FaceService::IDENTIFY_THRESHOLD;
        $reviewThreshold = $threshold - 0.08; // borderline band below the main threshold

        if ($score < $reviewThreshold) {
            return ['no_match', null];
        }

        // Load the patient and verify they belong to this hospital
        $ft = FaceTemplate::with('patient:id,full_name,date_of_birth,nida,gender,phone')
            ->find($candidate['template_id']);

        if (! $ft || $ft->hospital_id !== $hospitalId || ! $ft->patient) {
            return ['no_match', null];
        }

        $status = $score >= $threshold ? 'matched' : 'needs_review';
        return [$status, $ft->patient];
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
