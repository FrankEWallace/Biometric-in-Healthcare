<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\SupervisorOverride;
use App\Models\Visit;
use App\Models\VisitStage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SupervisorOverrideController extends Controller
{
    // -------------------------------------------------------------------------
    // GET /api/supervisor-overrides
    // -------------------------------------------------------------------------

    /**
     * List pending override requests for supervisors (admin, doctor, nurse).
     * Staff see their own requests. Supervisors see all pending in their hospital.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $query = SupervisorOverride::with([
            'visitStage.visit.patient:id,full_name,hospital_patient_id',
            'requestedBy:id,name,role',
            'supervisor:id,name,role',
        ])->whereHas('visitStage.visit', fn($q) =>
            $q->where('hospital_id', $user->hospital_id)
        );

        // Non-supervisors only see their own requests
        if (! $user->isAnyAdmin() && ! $user->isDoctor() && ! $user->isNurse()) {
            $query->where('requested_by', $user->id);
        }

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        } else {
            $query->where('status', 'pending');
        }

        return response()->json(['overrides' => $query->orderByDesc('requested_at')->get()]);
    }

    // -------------------------------------------------------------------------
    // POST /api/supervisor-overrides
    // -------------------------------------------------------------------------

    /**
     * Request a supervisor override when biometric fails at a stage.
     *
     * {
     *   "visit_stage_id":  12,
     *   "fallback_chain":  "fingerprint_and_face_failed",
     *   "staff_note":      "Patient has bandaged finger"
     * }
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'visit_stage_id' => 'required|integer|exists:visit_stages,id',
            'fallback_chain' => 'required|in:fingerprint_failed,fingerprint_and_face_failed',
            'staff_note'     => 'nullable|string|max:255',
        ]);

        $stage = VisitStage::with('visit')->findOrFail($data['visit_stage_id']);

        // Scope check
        if ($stage->visit->hospital_id !== $user->hospital_id) {
            return response()->json(['error' => 'Not found.'], 404);
        }

        if ($stage->isCompleted()) {
            return response()->json(['error' => 'Stage is already completed.'], 409);
        }

        // Only one pending override per stage
        if ($stage->hasPendingOverride()) {
            return response()->json([
                'error'    => 'A pending override request already exists for this stage.',
                'override' => $stage->supervisorOverride,
            ], 409);
        }

        $override = SupervisorOverride::create([
            'visit_stage_id' => $stage->id,
            'requested_by'   => $user->id,
            'status'         => 'pending',
            'fallback_chain' => $data['fallback_chain'],
            'staff_note'     => $data['staff_note'] ?? null,
            'requested_at'   => now(),
        ]);

        AuditLog::record($request, AuditLog::ACTION_STAGE_OVERRIDE_REQUESTED, $stage->visit->patient_id, null, null, [
            'visit_id'       => $stage->visit_id,
            'stage'          => $stage->stage,
            'override_id'    => $override->id,
            'fallback_chain' => $data['fallback_chain'],
        ]);

        return response()->json(['override' => $override->load('requestedBy:id,name,role')], 201);
    }

    // -------------------------------------------------------------------------
    // PUT /api/supervisor-overrides/{override}/resolve
    // -------------------------------------------------------------------------

    /**
     * Supervisor approves or denies the override request.
     * On approval: stage is marked as completed without biometric verification.
     *
     * {
     *   "decision":         "approved",      // or "denied"
     *   "supervisor_note":  "Verified by ID card"
     * }
     */
    public function resolve(Request $request, SupervisorOverride $override): JsonResponse
    {
        $user = $request->user();

        // Supervisor must be admin, doctor, or nurse in the same hospital
        $stage = $override->visitStage()->with('visit')->first();

        if ($stage->visit->hospital_id !== $user->hospital_id) {
            return response()->json(['error' => 'Not found.'], 404);
        }

        if (! $override->isPending()) {
            return response()->json(['error' => 'Override has already been resolved.'], 409);
        }

        $data = $request->validate([
            'decision'        => 'required|in:approved,denied',
            'supervisor_note' => 'nullable|string|max:255',
        ]);

        $override->resolve($user, $data['decision'], $data['supervisor_note'] ?? null);

        // On approval — complete the stage without a verification log
        if ($data['decision'] === 'approved') {
            $simulatedData = VisitStage::SIMULATED_DEFAULTS[$stage->stage] ?? null;

            $stage->update([
                'status'         => 'completed',
                'verified_by'    => $user->id,
                'verified_at'    => now(),
                'simulated_data' => $simulatedData,
            ]);
        }

        AuditLog::record($request, AuditLog::ACTION_STAGE_OVERRIDE_RESOLVED, $stage->visit->patient_id, null, null, [
            'visit_id'    => $stage->visit_id,
            'stage'       => $stage->stage,
            'override_id' => $override->id,
            'decision'    => $data['decision'],
        ]);

        return response()->json([
            'override' => $override->fresh(['requestedBy:id,name,role', 'supervisor:id,name,role']),
            'stage'    => $stage->fresh(),
        ]);
    }
}
