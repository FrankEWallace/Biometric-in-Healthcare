<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Patient;
use App\Models\Visit;
use App\Models\VisitStage;
use App\Services\VisitService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VisitStageController extends Controller
{
    public function __construct(private VisitService $visits) {}

    // -------------------------------------------------------------------------
    // GET /api/queue
    // -------------------------------------------------------------------------

    /**
     * Returns the active visit queue for the authenticated user's role.
     *
     * Clerk      → open visits (for checkout)
     * Nurse      → visits where triage is pending
     * Doctor     → visits where consultation is pending
     * Lab tech   → visits where laboratory is pending
     * Pharmacist → visits where pharmacy is pending
     * Admin      → all open visits
     */
    public function queue(Request $request): JsonResponse
    {
        $user  = $request->user();
        $stage = $user->assignedStage();

        $query = Visit::where('hospital_id', $user->hospital_id)
            ->where('status', 'open')
            ->with([
                'patient:id,full_name,hospital_patient_id,date_of_birth,gender',
                'stages' => fn($q) => $q->select('id', 'visit_id', 'stage', 'status', 'verified_at'),
            ])
            ->orderBy('opened_at');

        // Filter by the stage this role is responsible for
        if ($stage) {
            $query->whereHas('stages', fn($q) => $q
                ->where('stage', $stage)
                ->where('status', 'pending')
            );
        }

        return response()->json(['queue' => $query->get()]);
    }

    // -------------------------------------------------------------------------
    // POST /api/visits/{visit}/stages/{stage}/verify
    // -------------------------------------------------------------------------

    /**
     * Verify a patient's identity at a specific stage.
     * Runs the tiered biometric pipeline: fingerprint → face → failure.
     *
     * {
     *   "fingerprint_image": "<base64>",       // required
     *   "face_image":        "<base64>",       // optional fallback
     *   "gps_latitude":      ...,
     *   "gps_longitude":     ...,
     *   "wifi_ssid":         "..."
     * }
     */
    public function verify(Request $request, Visit $visit, string $stageName): JsonResponse
    {
        $user = $request->user();
        $this->authorizeHospital($request, $visit);

        if ($visit->isClosed()) {
            return response()->json(['error' => 'Cannot verify a closed visit.'], 409);
        }

        $stage = $visit->stages()->where('stage', $stageName)->first();

        if (! $stage) {
            return response()->json(['error' => 'Stage not found.'], 404);
        }

        if ($stage->isCompleted()) {
            return response()->json([
                'error'      => 'This stage has already been verified.',
                'verified_at' => $stage->verified_at,
            ], 409);
        }

        // Role check — only the assigned role can verify at this stage
        $allowedRoles = VisitStage::STAGE_ROLES[$stageName] ?? [];
        if (! empty($allowedRoles) && ! in_array($user->role, $allowedRoles)) {
            return response()->json([
                'error' => "Your role ({$user->role}) is not permitted to verify at the {$stageName} stage.",
            ], 403);
        }

        $data = $request->validate([
            'fingerprint_image' => 'required|string',
            'face_image'        => 'nullable|string',
            'gps_latitude'      => 'nullable|numeric',
            'gps_longitude'     => 'nullable|numeric',
            'wifi_ssid'         => 'nullable|string|max:100',
        ]);

        $patient  = $visit->patient;
        $hospital = $visit->hospital;

        $result = $this->visits->verifyStage(
            visit:            $visit,
            stage:            $stage,
            patient:          $patient,
            hospital:         $hospital,
            operatorId:       $user->id,
            fingerprintImage: $data['fingerprint_image'],
            faceImage:        $data['face_image'] ?? null,
            request:          $request,
        );

        AuditLog::record(
            $request,
            $result['matched'] ? AuditLog::ACTION_STAGE_VERIFIED : AuditLog::ACTION_FINGERPRINT_NO_MATCH,
            $patient->id,
            null,
            null,
            [
                'visit_id'            => $visit->id,
                'stage'               => $stageName,
                'modality'            => $result['modality'],
                'score'               => $result['score'],
                'verification_log_id' => $result['verification_log_id'],
            ]
        );

        if (! $result['matched']) {
            return response()->json([
                'matched'           => false,
                'fallback_exhausted' => $result['fallback_exhausted'],
                'message'           => 'Biometric verification failed. Request a supervisor override to proceed.',
            ], 422);
        }

        // Reload stage with fresh data for response
        $stage->refresh();

        return response()->json([
            'matched'             => true,
            'modality'            => $result['modality'],
            'score'               => $result['score'],
            'verification_log_id' => $result['verification_log_id'],
            'stage'               => $stage,
            'simulated_data'      => $stage->simulated_data,
        ]);
    }

    // -------------------------------------------------------------------------
    // PUT /api/visits/{visit}/stages/{stage}/data
    // -------------------------------------------------------------------------

    /**
     * Update simulated EMR data for a completed stage.
     * Staff can edit the pre-filled simulation (e.g. triage nurse adjusts vitals).
     *
     * {
     *   "simulated_data": { ... }
     * }
     */
    public function updateData(Request $request, Visit $visit, string $stageName): JsonResponse
    {
        $user = $request->user();
        $this->authorizeHospital($request, $visit);

        $stage = $visit->stages()->where('stage', $stageName)->first();

        if (! $stage || $stage->isPending()) {
            return response()->json([
                'error' => 'Stage must be verified before data can be submitted.',
            ], 422);
        }

        $allowedRoles = VisitStage::STAGE_ROLES[$stageName] ?? [];
        if (! empty($allowedRoles) && ! in_array($user->role, $allowedRoles)) {
            return response()->json(['error' => 'Not permitted.'], 403);
        }

        $data = $request->validate([
            'simulated_data' => 'required|array',
        ]);

        // Triage is the only stage that sets visit_type
        if ($stageName === 'triage' && isset($data['simulated_data']['visit_type_set'])) {
            $visitType = $data['simulated_data']['visit_type_set'];

            if (in_array($visitType, ['opd', 'ipd'])) {
                $visit->update(['visit_type' => $visitType]);
            }
        }

        $stage->update(['simulated_data' => $data['simulated_data']]);

        return response()->json([
            'stage'          => $stage->fresh(),
            'visit_type'     => $visit->fresh()->visit_type,
        ]);
    }

    // -------------------------------------------------------------------------
    // Private
    // -------------------------------------------------------------------------

    private function authorizeHospital(Request $request, Visit $visit): void
    {
        abort_if($visit->hospital_id !== $request->user()->hospital_id, 404);
    }
}
