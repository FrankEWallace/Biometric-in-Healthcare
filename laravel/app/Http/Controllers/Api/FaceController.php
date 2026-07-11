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
use App\Services\PatientAccessService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class FaceController extends Controller
{
    public function __construct(
        private FaceService          $face,
        private GeofenceService      $geofence,
        private HomisService         $homis,
        private PatientAccessService $access,
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
            // 1. Persist the new template first so we have a valid template_id
            //    before touching the FAISS index.
            $ft = new FaceTemplate();
            $ft->patient_id    = $patient->id;
            $ft->hospital_id   = $patient->hospital_id;
            $ft->enrolled_by   = $request->user()->id;
            $ft->quality_score = $qualityScore;
            $ft->is_active     = true;
            $ft->setTemplate($result['embedding']);
            $ft->save();

            // 2. Enforce per-patient template cap — evict oldest if needed.
            if ($activeTemplates->count() >= FaceService::MAX_TEMPLATES_PER_PATIENT) {
                $oldest = $activeTemplates->first();
                $oldest->update(['is_active' => false]);

                // Rebuild the patient's FAISS vectors from the surviving templates.
                // This is atomic relative to the DB transaction — if any FAISS call
                // fails we throw and the whole transaction rolls back.
                try {
                    $this->face->removeFromIndex($patient->id);

                    $activeTemplates->skip(1)->each(function (FaceTemplate $survivor) use ($patient) {
                        try {
                            $decoded = $survivor->getTemplate();
                        } catch (\Exception $e) {
                            Log::error("FaceTemplate {$survivor->id} decryption failed during re-enroll: {$e->getMessage()}");
                            return;
                        }
                        if ($decoded && isset($decoded['embedding'])) {
                            $this->face->enrollToIndex($patient->id, $survivor->id, $decoded['embedding']);
                        }
                    });
                } catch (\RuntimeException $e) {
                    throw $e; // propagate to roll back the DB transaction
                }
            }

            // 3. Register the new template in FAISS.
            try {
                $this->face->enrollToIndex($patient->id, $ft->id, $result['embedding']);
            } catch (\RuntimeException $e) {
                throw $e; // propagate to roll back the DB transaction
            }

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

        // ── Self-heal a lost index ────────────────────────────────────────────
        // Zero candidates while active templates exist in the DB means the
        // on-disk FAISS index was lost (e.g. ephemeral-disk redeploy).
        // Rebuild it from the encrypted templates and retry once.
        if (empty($candidates) && FaceTemplate::where('is_active', true)->exists()) {
            try {
                Log::warning('FAISS returned no candidates while active face templates exist — rebuilding index.');
                $this->face->rebuildIndex($this->activeTemplatePayload());

                $faissResult = $this->face->identify($probeEmbedding, topK: 5);
                $candidates  = $faissResult['candidates'] ?? [];
            } catch (\RuntimeException $e) {
                Log::error('FAISS self-heal rebuild failed: ' . $e->getMessage());
            }
        }

        if (empty($candidates)) {
            $log = $this->writeLog($operator->id, $hospital->id, null, 0.0, 'no_match', $data);
            return response()->json(['status' => 'no_match', 'score' => 0.0, 'patient' => null, 'log_id' => $log->id]);
        }

        // ── Resolve identity NATIONALLY (best valid candidate, hospital-agnostic) ─
        [$status, $patient, $score] = $this->resolveIdentity($candidates);

        // ── Access-control seam — decided AFTER identity, by hospital ─────────
        // A resolved patient from another hospital is NOT a no_match: identity
        // was found; the operator is simply not authorized for the record. Do
        // not leak any PII in that case — but still audit the identified id.
        if ($patient !== null && ! $this->access->authorizePatientAccess($operator, $patient)) {
            $status = 'access_restricted';
        }

        $log = $this->writeLog(
            operatorId:   $operator->id,
            hospitalId:   $hospital->id,
            patientId:    $patient?->id,
            score:        $score,
            status:       $status,
            locationData: $data,
        );

        $auditAction = match ($status) {
            'matched'            => AuditLog::ACTION_FACE_MATCH,
            'access_restricted'  => AuditLog::ACTION_ACCESS_RESTRICTED,
            default              => AuditLog::ACTION_FACE_NO_MATCH,
        };

        AuditLog::record($request, $auditAction, $patient?->id, null, $status, [
            'score'  => round($score, 4),
            'log_id' => $log->id,
        ]);

        // ── Access denied: identity found, records withheld, zero PII ─────────
        if ($status === 'access_restricted') {
            return response()->json([
                'status'    => 'access_restricted',
                'score'     => round($score, 4),
                'patient'   => null,
                'log_id'    => $log->id,
                'ehr'       => null,
                'insurance' => null,
            ]);
        }

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
        try {
            $count = $this->face->rebuildIndex($this->activeTemplatePayload());
        } catch (\RuntimeException $e) {
            return response()->json(['error' => 'Index rebuild failed: ' . $e->getMessage()], 500);
        }

        return response()->json([
            'message'       => 'FAISS index rebuilt successfully.',
            'indexed_count' => $count,
        ]);
    }

    /**
     * Decrypted [patient_id, template_id, embedding] payload for every active
     * face template, ready for FaceService::rebuildIndex(). The FAISS index
     * is global (one per Python service), so the rebuild always covers all
     * hospitals — per-hospital scoping happens at match time in
     * interpretCandidate().
     */
    private function activeTemplatePayload(): array
    {
        return FaceTemplate::where('is_active', true)
            ->get()
            ->map(function (FaceTemplate $ft) {
                try {
                    $decoded = $ft->getTemplate();
                } catch (\Exception $e) {
                    Log::error("FaceTemplate {$ft->id} decryption failed during index rebuild: {$e->getMessage()}");
                    return null;
                }
                if (! $decoded || empty($decoded['embedding'])) {
                    Log::warning("FaceTemplate {$ft->id} has empty or missing embedding — skipped in rebuild.");
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
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/face/verify-confirm
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Record a staff manual confirmation of a borderline face match.
     *
     * Called when a nurse selects "Confirm Manually" on the needs_review dialog.
     * Creates an audit trail so the decision is traceable.
     *
     * Fields:
     *   log_id      (int,    required) — verification_logs.id from the verify call
     *   patient_id  (int,    required) — patient being confirmed
     */
    public function confirmReview(Request $request): JsonResponse
    {
        $data = $request->validate([
            'log_id'     => 'required|integer|exists:verification_logs,id',
            'patient_id' => 'required|integer|exists:patients,id',
        ]);

        $log = VerificationLog::findOrFail($data['log_id']);

        // Ensure the log belongs to this operator's hospital
        if ($log->hospital_id !== $request->user()->hospital_id) {
            return response()->json(['error' => 'Not found.'], 404);
        }

        if ($log->status !== 'needs_review') {
            return response()->json(['error' => 'This log is not in needs_review status.'], 422);
        }

        $log->update(['status' => 'manually_confirmed']);

        AuditLog::record($request, AuditLog::ACTION_FACE_MANUAL_CONFIRM, $data['patient_id'], null, null, [
            'log_id'     => $data['log_id'],
            'score'      => $log->score,
            'confirmed_by' => $request->user()->id,
        ]);

        return response()->json(['message' => 'Manual confirmation recorded.']);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Classify the top FAISS candidate into a decision status.
     *
     * Returns [status, patient|null].
     * Status values: 'matched', 'needs_review', 'no_match'
     */
    /**
     * Resolve identity nationally: pick the highest-scoring candidate with a
     * live template + patient, regardless of hospital. Candidates arrive sorted
     * by score descending. Returns [status, patient|null, score] where status is
     * the IDENTITY verdict only ('matched' | 'needs_review' | 'no_match') — the
     * hospital access decision is applied separately by the caller.
     */
    private function resolveIdentity(array $candidates): array
    {
        $threshold       = FaceService::IDENTIFY_THRESHOLD;
        $reviewThreshold = $threshold - 0.08; // borderline band below the main threshold

        foreach ($candidates as $candidate) {
            $score = (float) $candidate['score'];

            // Sorted descending — once below the review band, nothing qualifies.
            if ($score < $reviewThreshold) {
                break;
            }

            // hospital_id is required for the access-control check below.
            $ft = FaceTemplate::with('patient:id,hospital_id,full_name,date_of_birth,nida,gender,phone')
                ->find($candidate['template_id']);

            // Skip stale/orphaned templates and keep scanning down the list.
            if (! $ft || ! $ft->patient) {
                continue;
            }

            $status = $score >= $threshold ? 'matched' : 'needs_review';
            return [$status, $ft->patient, $score];
        }

        $topScore = ! empty($candidates) ? (float) (reset($candidates)['score'] ?? 0.0) : 0.0;
        return ['no_match', null, $topScore];
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
