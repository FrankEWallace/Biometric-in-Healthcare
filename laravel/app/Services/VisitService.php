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

class VisitService
{
    /** Minimum shared fingers required to fuse a four-finger hand match. Mirrors VerificationController. */
    private const MIN_HAND_FINGERS = 3;

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
     *   four-finger hand embedding → face (if available + hospital enabled)
     *   → failure. Single-finger contactless minutiae, if supplied, is
     *   reported for audit purposes only — it can never complete a stage
     *   (non-discriminative on contactless finger photos, EER 42–50%).
     *
     * On success: creates a VerificationLog linked to the stage and marks
     * the stage as completed.
     *
     * Returns an array with keys:
     *   matched        bool
     *   modality       'hand'|'face'|null
     *   score          float
     *   verification_log_id  int|null
     *   fallback_exhausted   bool   — true when hand and face both failed
     */
    public function verifyStage(
        Visit      $visit,
        VisitStage $stage,
        Patient    $patient,
        Hospital   $hospital,
        int        $operatorId,
        string     $handImage,
        string     $hand,
        ?string    $faceImage,
        ?string    $fingerprintImage,
        Request    $request,
    ): array {
        // ── 1. Four-finger hand embedding — the primary matcher ────────────────
        $handResult = $this->tryHand($patient, $handImage, $hand);

        if ($handResult['matched']) {
            $log = $this->logAndCompleteStage(
                visit:            $visit,
                stage:            $stage,
                patient:          $patient,
                hospital:         $hospital,
                operatorId:       $operatorId,
                modality:         'hand',
                score:            $handResult['score'],
                request:          $request,
            );

            return [
                'matched'              => true,
                'modality'             => 'hand',
                'score'                => $handResult['score'],
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

        // ── 3. Single-finger minutiae — advisory only, never completes a stage ─
        // Reported (if supplied) purely so the audit log/log entry captures the
        // legacy signal; non-discriminative on contactless finger photos.
        $advisoryScore = $fingerprintImage !== null
            ? $this->tryFingerprint($patient, $fingerprintImage)['score']
            : $handResult['score'];

        // ── 4. Both decisive tiers failed — log the failed attempt ─────────────
        VerificationLog::create([
            'patient_id'     => $patient->id,
            'operator_id'    => $operatorId,
            'hospital_id'    => $hospital->id,
            'visit_stage_id' => $stage->id,
            'score'          => $advisoryScore,
            'status'         => 'no_match',
            'modality'       => 'hand',
            'gps_latitude'   => $request->input('gps_latitude'),
            'gps_longitude'  => $request->input('gps_longitude'),
            'wifi_ssid'      => $request->input('wifi_ssid'),
        ]);

        return [
            'matched'             => false,
            'modality'            => null,
            'score'               => $advisoryScore,
            'verification_log_id' => null,
            'fallback_exhausted'  => true,
        ];
    }

    // ------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------

    /**
     * Four-finger contactless embedding tier — the primary matcher.
     * Mirrors VerificationController::verifyHand's placeholder-safe gate:
     * only accepts when a calibrated threshold is configured AND the matcher
     * that actually ran is a learned embedding (not the minutiae placeholder).
     */
    private function tryHand(Patient $patient, string $base64HandImage, string $hand): array
    {
        $candidateHand = $this->loadPatientHand($patient);

        if ($candidateHand === null) {
            return ['matched' => false, 'score' => 0.0];
        }

        try {
            $processed = $this->fingerprint->processHand($base64HandImage, $hand, 'contactless');
        } catch (\Throwable) {
            return ['matched' => false, 'score' => 0.0];
        }

        $probe = [];
        foreach ($processed['fingers'] ?? [] as $finger) {
            $probe[$finger['finger_position']] = $finger['template'];
        }

        if (count($probe) < self::MIN_HAND_FINGERS) {
            return ['matched' => false, 'score' => 0.0];
        }

        try {
            $result = $this->fingerprint->matchHand($probe, [$candidateHand], 'contactless');
        } catch (\Throwable) {
            return ['matched' => false, 'score' => 0.0];
        }

        $fusedScore        = (float) ($result['score'] ?? 0.0);
        $matchedPatientId  = $result['patient_id'] ?? null;
        $matcherName       = $result['matcher'] ?? ($processed['matcher'] ?? 'unknown');

        $threshold        = config('services.fingerprint.contactless_match_threshold');
        $usingPlaceholder = ! str_contains($matcherName, 'embedding');

        if ($threshold === null || $usingPlaceholder) {
            return ['matched' => false, 'score' => $fusedScore];
        }

        $matched = $matchedPatientId !== null
            && (int) $matchedPatientId === $patient->id
            && $fusedScore >= (float) $threshold;

        return ['matched' => $matched, 'score' => $fusedScore];
    }

    /**
     * Single-patient adaptation of VerificationController::loadCandidateHands:
     * one fused-matchable "hand" for this patient, or null if fewer than
     * MIN_HAND_FINGERS gallery-lead templates are enrolled.
     */
    private function loadPatientHand(Patient $patient): ?array
    {
        $rows = Fingerprint::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->where('is_gallery_lead', true)
            ->get(['id', 'patient_id', 'finger_position', 'template']);

        $fingers = [];
        foreach ($rows as $fp) {
            $template = $fp->getTemplate();
            if ($template === null) {
                continue;
            }
            $fingers[$fp->finger_position] = $template;
        }

        if (count($fingers) < self::MIN_HAND_FINGERS) {
            return null;
        }

        return ['patient_id' => $patient->id, 'fingers' => $fingers];
    }

    /**
     * Single-finger contactless minutiae — advisory only. Never sets
     * matched=true from the caller's perspective (score is reported for
     * audit purposes; see verifyStage). Non-discriminative on contactless
     * finger photos (EER 42–50%).
     */
    private function tryFingerprint(Patient $patient, string $base64Image): array
    {
        $fp = Fingerprint::where('patient_id', $patient->id)
            ->where('is_active', true)
            ->where('template_format', 'minutiae_v1')
            ->where(fn($q) => $q->where('is_primary', true)->orWhereNull('is_primary'))
            ->orderByDesc('is_primary')
            ->first();

        if (! $fp) {
            return ['matched' => false, 'score' => 0.0];
        }

        try {
            $tmpPath = $this->base64ToTempFile($base64Image);
            $result  = $this->fingerprint->verifyAgainstAll($tmpPath, [
                ['fingerprint_id' => $fp->id, 'template' => $fp->getTemplate()],
            ]);
            @unlink($tmpPath);

            return [
                'matched' => false, // advisory only — see verifyStage
                'score'   => $result['score'] ?? 0.0,
            ];
        } catch (\Throwable) {
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
            // Passive liveness gate — reject spoofed images before embedding
            $liveness = $this->face->liveness($base64Image);
            if (! ($liveness['is_live'] ?? false)) {
                return ['matched' => false, 'score' => 0.0];
            }

            $probe      = $this->face->process($base64Image);
            $candidates = [['patient_id' => $patient->id, 'embedding' => $faceTemplate->getTemplate()['embedding'] ?? null]];
            $result     = $this->face->match($probe, $candidates);

            $score   = (float) ($result['score'] ?? 0.0);
            $matched = $score >= FaceService::MATCH_THRESHOLD;

            return ['matched' => $matched, 'score' => $score];
        } catch (\Throwable) {
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
