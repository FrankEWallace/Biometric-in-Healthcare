<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Fingerprint;
use App\Models\VerificationLog;
use App\Services\FingerprintService;
use App\Services\GeofenceService;
use App\Services\HomisService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VerificationController extends Controller
{
    /** Minutiae match score threshold (0–100 scale, 20 recommended starting point). */
    private const MATCH_THRESHOLD = 20.0;

    public function __construct(
        private FingerprintService $fingerprint,
        private GeofenceService    $geofence,
        private HomisService       $homis,
    ) {}

    /**
     * POST /api/verify
     *
     * Two-pass matching strategy:
     *   Pass 1 — probe vs. primary fingerprints only (fast, typical case).
     *            If a match is found above threshold, return immediately.
     *   Pass 2 — probe vs. remaining non-primary active fingerprints (fallback).
     *            Runs only when pass-1 finds no match.
     *
     * This halves the average Python round-trips in a well-enrolled dataset.
     */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'image'         => 'required|string',
            'gps_latitude'  => 'nullable|numeric|between:-90,90',
            'gps_longitude' => 'nullable|numeric|between:-180,180',
            'wifi_ssid'     => 'nullable|string|max:100',
        ]);

        $operator = $request->user();
        $hospital = $operator->hospital;

        // ------------------------------------------------------------------
        // 1. Geofence check
        // ------------------------------------------------------------------
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

        // ------------------------------------------------------------------
        // 2. Extract probe template
        // ------------------------------------------------------------------
        try {
            $result        = $this->fingerprint->process($data['image']);
            $probeTemplate = $result['template'];
        } catch (\Throwable $e) {
            $this->writeLog($operator->id, $hospital->id, null, null, null, 'error', $data, $e->getMessage());
            return response()->json(['error' => 'Feature extraction failed: ' . $e->getMessage()], 500);
        }

        // ------------------------------------------------------------------
        // 3. Pass 1 — match against PRIMARY fingerprints only
        //    Uses ix_fp_hospital_primary_active index: (hospital_id, is_primary, is_active)
        // ------------------------------------------------------------------
        $primaryFingerprints = $this->loadFingerprints($hospital->id, primaryOnly: true);

        [$score, $matchedFp] = $this->runMatch($probeTemplate, $primaryFingerprints);

        // ------------------------------------------------------------------
        // 4. Pass 2 — fallback to non-primary fingerprints if pass-1 missed
        //    Uses ix_fp_hospital_active index: (hospital_id, is_active)
        // ------------------------------------------------------------------
        if ($score < self::MATCH_THRESHOLD) {
            $nonPrimaryFingerprints = $this->loadFingerprints($hospital->id, primaryOnly: false)
                ->whereNotIn('id', $primaryFingerprints->pluck('id'));

            if ($nonPrimaryFingerprints->isNotEmpty()) {
                [$score2, $matchedFp2] = $this->runMatch($probeTemplate, $nonPrimaryFingerprints);
                if ($score2 > $score) {
                    $score     = $score2;
                    $matchedFp = $matchedFp2;
                }
            }
        }

        // ------------------------------------------------------------------
        // 5. Resolve result and write verification audit log
        // ------------------------------------------------------------------
        $matched        = $score >= self::MATCH_THRESHOLD && $matchedFp !== null;
        $matchedPatient = $matched ? $matchedFp->patient : null;
        $status         = $matched ? 'matched' : 'no_match';

        // ── Failure tracking and lock ─────────────────────────────────────────
        $justLocked = false;

        if (! $matched && $matchedFp !== null) {
            $justLocked = $matchedFp->recordFailure();
        } elseif ($matched) {
            // Successful match — reset failure counters
            $matchedFp->unlock();
        }

        $log = $this->writeLog(
            operatorId:    $operator->id,
            hospitalId:    $hospital->id,
            patientId:     $matchedPatient?->id,
            fingerprintId: $matched ? $matchedFp->id : null,
            score:         $score,
            status:        $status,
            locationData:  $data,
        );

        $auditAction = $matched
            ? AuditLog::ACTION_FINGERPRINT_MATCH
            : AuditLog::ACTION_FINGERPRINT_NO_MATCH;

        AuditLog::record($request, $auditAction, $matchedPatient?->id, null, $status, [
            'score'   => round($score, 4),
            'log_id'  => $log->id,
        ]);

        if ($justLocked && $matchedFp !== null) {
            AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_LOCK, $matchedFp->patient_id, null, null, [
                'fingerprint_id'  => $matchedFp->id,
                'failed_attempts' => $matchedFp->failed_attempts,
                'window_hours'    => \App\Models\Fingerprint::LOCK_WINDOW_HOURS,
            ]);
        }

        // ------------------------------------------------------------------
        // 6. GoT-HoMIS enrichment (only on successful match)
        //    Failures are non-fatal — verification result is returned regardless
        // ------------------------------------------------------------------
        $ehr       = null;
        $insurance = null;

        if ($matched && $matchedPatient !== null) {
            $homisId = (string) $matchedPatient->id;

            $ehr = $this->homis->getPatientRecord($homisId);
            AuditLog::record($request, 'ehr_access', $matchedPatient->id, 'patient_registration',
                $ehr ? '200' : 'unavailable');

            $insurance = $this->homis->getInsuranceEligibility($homisId);
            AuditLog::record($request, 'insurance_check', $matchedPatient->id, 'insurance',
                $insurance ? '200' : 'unavailable');
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

    /**
     * GET /api/verify/logs
     *
     * super_admin/admin: all hospital logs with operator name
     * doctor:            patient-centric — sees nurse name, no score
     * nurse:             own logs only
     */
    public function logs(Request $request): JsonResponse
    {
        $user  = $request->user();
        $query = VerificationLog::with(['patient:id,full_name', 'operator:id,name', 'fingerprint:id,finger_position']);

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } elseif ($user->isAnyAdmin()) {
            $query->where('hospital_id', $user->hospital_id);
        } elseif ($user->isDoctor()) {
            $query->where('hospital_id', $user->hospital_id);
        } else {
            // Nurse: own logs only
            $query->where('operator_id', $user->id);
        }

        if ($v = $request->query('patient_id'))                   { $query->where('patient_id',  $v); }
        if ($v = $request->query('operator_id') and $user->isAnyAdmin()) { $query->where('operator_id', $v); }
        if ($v = $request->query('status'))                        { $query->where('status',      $v); }

        $logs = $query->orderByDesc('created_at')
                      ->paginate($request->integer('per_page', 20));

        // Doctors don't see match score
        if ($user->isDoctor()) {
            $logs->getCollection()->transform(fn ($log) => tap($log, fn ($l) => $l->makeHidden('score')));
        }

        return response()->json($logs);
    }

    /**
     * GET /api/verify/logs/{log}
     */
    public function showLog(Request $request, VerificationLog $log): JsonResponse
    {
        $user = $request->user();

        if ($user->isSuperAdmin()) {
            // full access
        } elseif ($user->isAnyAdmin() || $user->isDoctor()) {
            abort_if($log->hospital_id !== $user->hospital_id, 404);
        } else {
            // Nurse: own logs only
            abort_if($log->operator_id !== $user->id, 404);
        }

        $log->load([
            'patient:id,full_name,date_of_birth,nida',
            'operator:id,name',
            'fingerprint:id,finger_position,quality_score',
        ]);

        if ($user->isDoctor()) {
            $log->makeHidden('score');
        }

        return response()->json(['log' => $log]);
    }

    // ------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------

    /**
     * Load active fingerprints for a hospital directly by hospital_id
     * (no JOIN needed — hospital_id is denormalised onto fingerprints).
     *
     * Only gallery leads are loaded so 1:N identification stays
     * one-template-per-finger — galleries of 3 are used for 1:1 verification
     * only, avoiding FAR inflation and 3x match latency at hospital scale.
     */
    private function loadFingerprints(int $hospitalId, bool $primaryOnly): Collection
    {
        return Fingerprint::where('hospital_id', $hospitalId)
            ->where('is_active', true)
            ->where('is_gallery_lead', true)
            ->when($primaryOnly, fn ($q) => $q->where('is_primary', true))
            ->with('patient:id,full_name,date_of_birth,nida,gender,phone')
            ->get();
    }

    /**
     * Send a candidate list to Python /match and return [score, Fingerprint|null].
     *
     * @param  array      $probeTemplate
     * @param  Collection $fingerprints
     * @return array{float, Fingerprint|null}
     */
    private function runMatch(array $probeTemplate, Collection $fingerprints): array
    {
        if ($fingerprints->isEmpty()) {
            return [0.0, null];
        }

        $candidates = $fingerprints
            ->map(fn (Fingerprint $fp) => [
                'patient_id' => $fp->id,          // fingerprint.id used as candidate key
                'template'   => $fp->getTemplate(),
            ])
            ->filter(fn ($c) => $c['template'] !== null)
            ->values()
            ->all();

        if (empty($candidates)) {
            return [0.0, null];
        }

        $result    = $this->fingerprint->match($probeTemplate, $candidates);
        $score     = (float) $result['score'];
        $matchedFp = $fingerprints->firstWhere('id', $result['patient_id']);

        return [$score, $matchedFp];
    }

    private function writeLog(
        int     $operatorId,
        int     $hospitalId,
        ?int    $patientId,
        ?int    $fingerprintId,
        ?float  $score,
        string  $status,
        array   $locationData = [],
        ?string $errorMessage = null,
    ): VerificationLog {
        return VerificationLog::create([
            'operator_id'    => $operatorId,
            'hospital_id'    => $hospitalId,
            'patient_id'     => $patientId,
            'fingerprint_id' => $fingerprintId,
            'score'          => $score,
            'status'         => $status,
            'gps_latitude'   => $locationData['gps_latitude']  ?? null,
            'gps_longitude'  => $locationData['gps_longitude'] ?? null,
            'wifi_ssid'      => $locationData['wifi_ssid']     ?? null,
            'error_message'  => $errorMessage,
        ]);
    }
}
