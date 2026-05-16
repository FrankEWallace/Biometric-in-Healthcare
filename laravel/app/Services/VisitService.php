<?php

namespace App\Services;

use App\Models\Fingerprint;
use App\Models\FaceTemplate;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\SupervisorOverride;
use App\Models\VerificationLog;
use App\Models\Visit;
use App\Models\VisitStage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class VisitService
{
    public function __construct(
        private FingerprintService $fingerprint,
        private FaceService        $face,
    ) {}

    // ------------------------------------------------------------------
    // Visit lifecycle
    // ------------------------------------------------------------------

    /**
     * Open a new visit for a patient. Creates the visit record and
     * pre-populates all 6 stage rows as pending.
     * Marks clerk_checkin as completed immediately using the provided
     * verification log.
     */
    public function openVisit(Patient $patient, int $clerkId, int $verificationLogId): Visit
    {
        return DB::transaction(function () use ($patient, $clerkId, $verificationLogId) {
            $visit = Visit::create([
                'hospital_id' => $patient->hospital_id,
                'patient_id'  => $patient->id,
                'opened_by'   => $clerkId,
                'visit_type'  => 'pending',
                'status'      => 'open',
                'opened_at'   => now(),
            ]);

            $stages = array_keys(VisitStage::STAGE_ROLES);

            foreach ($stages as $stageName) {
                VisitStage::create([
                    'visit_id' => $visit->id,
                    'stage'    => $stageName,
                    'status'   => 'pending',
                ]);
            }

            // Complete clerk_checkin immediately — the verification that opened the visit
            $checkin = $visit->stages()->where('stage', 'clerk_checkin')->first();
            $checkin->update([
                'status'               => 'completed',
                'verified_by'          => $clerkId,
                'verification_log_id'  => $verificationLogId,
                'verified_at'          => now(),
                'simulated_data'       => null,
            ]);

            // Link the verification log to this stage
            VerificationLog::where('id', $verificationLogId)
                ->update(['visit_stage_id' => $checkin->id]);

            return $visit->load('stages', 'patient');
        });
    }

    /**
     * Close a visit. Marks clerk_checkout as completed using the provided
     * verification log and sets visit status to closed.
     */
    public function closeVisit(Visit $visit, int $clerkId, int $verificationLogId): Visit
    {
        return DB::transaction(function () use ($visit, $clerkId, $verificationLogId) {
            $checkout = $visit->stages()->where('stage', 'clerk_checkout')->first();
            $checkout->update([
                'status'              => 'completed',
                'verified_by'         => $clerkId,
                'verification_log_id' => $verificationLogId,
                'verified_at'         => now(),
            ]);

            VerificationLog::where('id', $verificationLogId)
                ->update(['visit_stage_id' => $checkout->id]);

            $visit->update([
                'status'    => 'closed',
                'closed_by' => $clerkId,
                'closed_at' => now(),
            ]);

            return $visit->fresh(['stages.verifiedBy', 'patient', 'openedBy', 'closedBy']);
        });
    }

    /**
     * Reopen a same-day closed visit. Only permitted on visits closed today.
     */
    public function reopenVisit(Visit $visit, int $clerkId, string $reason): Visit
    {
        return DB::transaction(function () use ($visit, $clerkId, $reason) {
            $visit->update([
                'status'        => 'open',
                'closed_by'     => null,
                'closed_at'     => null,
                'reopen_count'  => $visit->reopen_count + 1,
                'reopen_reason' => $reason,
            ]);

            // Reset clerk_checkout so it must be re-verified on next close
            $visit->stages()->where('stage', 'clerk_checkout')->update([
                'status'              => 'pending',
                'verified_by'         => null,
                'verification_log_id' => null,
                'verified_at'         => null,
            ]);

            return $visit->fresh(['stages', 'patient']);
        });
    }

    // ------------------------------------------------------------------
    // Stage biometric verification pipeline
    // ------------------------------------------------------------------

    /**
     * Run the tiered biometric pipeline for a stage:
     *   fingerprint → face (if available + hospital enabled) → failure
     *
     * On success: creates a VerificationLog linked to the stage and marks
     * the stage as completed.
     *
     * Returns an array with keys:
     *   matched        bool
     *   modality       'fingerprint'|'face'|null
     *   score          float
     *   verification_log_id  int|null
     *   fallback_exhausted   bool   — true when both biometrics failed
     */
    public function verifyStage(
        Visit      $visit,
        VisitStage $stage,
        Patient    $patient,
        Hospital   $hospital,
        int        $operatorId,
        string     $fingerprintImage,
        ?string    $faceImage,
        Request    $request,
    ): array {
        // ── 1. Fingerprint verification ───────────────────────────────────────
        $fpResult = $this->tryFingerprint($patient, $fingerprintImage);

        if ($fpResult['matched']) {
            $log = $this->logAndCompleteStage(
                visit:            $visit,
                stage:            $stage,
                patient:          $patient,
                hospital:         $hospital,
                operatorId:       $operatorId,
                modality:         'fingerprint',
                score:            $fpResult['score'],
                request:          $request,
            );

            return [
                'matched'              => true,
                'modality'             => 'fingerprint',
                'score'                => $fpResult['score'],
                'verification_log_id'  => $log->id,
                'fallback_exhausted'   => false,
            ];
        }

        // ── 2. Face fallback ──────────────────────────────────────────────────
        if ($faceImage && $hospital->face_recognition_enabled) {
            $faceResult = $this->tryFace($patient, $faceImage);

            if ($faceResult['matched']) {
                $log = $this->logAndCompleteStage(
                    visit:      $visit,
                    stage:      $stage,
                    patient:    $patient,
                    hospital:   $hospital,
                    operatorId: $operatorId,
                    modality:   'face',
                    score:      $faceResult['score'],
                    request:    $request,
                );

                return [
                    'matched'             => true,
                    'modality'            => 'face',
                    'score'               => $faceResult['score'],
                    'verification_log_id' => $log->id,
                    'fallback_exhausted'  => false,
                ];
            }
        }

        // ── 3. Both failed — log the failed attempt ───────────────────────────
        VerificationLog::create([
            'patient_id'     => $patient->id,
            'operator_id'    => $operatorId,
            'hospital_id'    => $hospital->id,
            'visit_stage_id' => $stage->id,
            'score'          => $fpResult['score'],
            'status'         => 'no_match',
            'modality'       => 'fingerprint',
            'gps_latitude'   => $request->input('gps_latitude'),
            'gps_longitude'  => $request->input('gps_longitude'),
            'wifi_ssid'      => $request->input('wifi_ssid'),
        ]);

        return [
            'matched'             => false,
            'modality'            => null,
            'score'               => $fpResult['score'],
            'verification_log_id' => null,
            'fallback_exhausted'  => true,
        ];
    }

    // ------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------

    private function tryFingerprint(Patient $patient, string $base64Image): array
    {
        $fp = Fingerprint::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->where('template_format', 'sourceafis_v1')
            ->where(fn($q) => $q->where('is_primary', true)->orWhereNull('is_primary'))
            ->orderByDesc('is_primary')
            ->first();

        if (! $fp) {
            return ['matched' => false, 'score' => 0.0];
        }

        try {
            $tmpPath = $this->base64ToTempFile($base64Image);
            $result  = $this->fingerprint->verify($tmpPath, $fp->getTemplate(), $patient->id);
            @unlink($tmpPath);

            return [
                'matched' => $result['verdict'] === 'MATCH',
                'score'   => $result['score'] ?? 0.0,
            ];
        } catch (RuntimeException) {
            return ['matched' => false, 'score' => 0.0];
        }
    }

    private function tryFace(Patient $patient, string $base64Image): array
    {
        $faceTemplate = FaceTemplate::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->first();

        if (! $faceTemplate) {
            return ['matched' => false, 'score' => 0.0];
        }

        try {
            $probe      = $this->face->process($base64Image);
            $candidates = [['patient_id' => $patient->id, 'embedding' => $faceTemplate->getEmbedding()]];
            $result     = $this->face->match($probe, $candidates);

            $score   = (float) ($result['score'] ?? 0.0);
            $matched = $score >= FaceService::MATCH_THRESHOLD;

            return ['matched' => $matched, 'score' => $score];
        } catch (RuntimeException) {
            return ['matched' => false, 'score' => 0.0];
        }
    }

    private function logAndCompleteStage(
        Visit      $visit,
        VisitStage $stage,
        Patient    $patient,
        Hospital   $hospital,
        int        $operatorId,
        string     $modality,
        float      $score,
        Request    $request,
    ): VerificationLog {
        return DB::transaction(function () use (
            $visit, $stage, $patient, $hospital, $operatorId, $modality, $score, $request
        ) {
            $log = VerificationLog::create([
                'patient_id'     => $patient->id,
                'operator_id'    => $operatorId,
                'hospital_id'    => $hospital->id,
                'visit_stage_id' => $stage->id,
                'score'          => $score,
                'status'         => 'matched',
                'modality'       => $modality,
                'gps_latitude'   => $request->input('gps_latitude'),
                'gps_longitude'  => $request->input('gps_longitude'),
                'wifi_ssid'      => $request->input('wifi_ssid'),
            ]);

            $simulatedData = VisitStage::SIMULATED_DEFAULTS[$stage->stage] ?? null;

            $stage->update([
                'status'              => 'completed',
                'verified_by'         => $operatorId,
                'verification_log_id' => $log->id,
                'verified_at'         => now(),
                'simulated_data'      => $simulatedData,
            ]);

            return $log;
        });
    }

    private function base64ToTempFile(string $base64Image): string
    {
        $binary  = base64_decode($base64Image);
        $tmpPath = tempnam(sys_get_temp_dir(), 'fp_') . '.jpg';
        file_put_contents($tmpPath, $binary);

        return $tmpPath;
    }
}
