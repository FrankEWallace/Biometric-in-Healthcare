<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Patient;
use App\Models\Visit;
use App\Models\VerificationLog;
use App\Services\PatientService;
use App\Services\VisitService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VisitController extends Controller
{
    public function __construct(
        private VisitService   $visits,
        private PatientService $patients,
    ) {}

    // -------------------------------------------------------------------------
    // GET /api/visits
    // -------------------------------------------------------------------------

    /**
     * List visits for the authenticated user's hospital.
     * Admin sees all. Clerk sees open visits. Others see their stage-relevant visits.
     */
    public function index(Request $request): JsonResponse
    {
        $user  = $request->user();
        $query = Visit::where('hospital_id', $user->hospital_id)
            ->with(['patient:id,full_name,hospital_patient_id', 'openedBy:id,name,role'])
            ->orderByDesc('opened_at');

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        if ($request->filled('visit_type')) {
            $query->where('visit_type', $request->input('visit_type'));
        }

        if ($request->filled('date')) {
            $query->whereDate('opened_at', $request->input('date'));
        } else {
            // Default: today only
            $query->whereDate('opened_at', today());
        }

        return response()->json($query->paginate($request->integer('per_page', 20)));
    }

    // -------------------------------------------------------------------------
    // POST /api/visits
    // -------------------------------------------------------------------------

    /**
     * Open a new visit (clerk check-in).
     *
     * {
     *   "patient_id":           123,
     *   "verification_log_id":  456,   // fingerprint/face log from clerk scan
     *   "gps_latitude":         ...,   // optional — forwarded to log
     *   "gps_longitude":        ...,
     *   "wifi_ssid":            ...
     * }
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'patient_id'          => 'required|integer|exists:patients,id',
            'verification_log_id' => 'required|integer|exists:verification_logs,id',
        ]);

        $patient = Patient::findOrFail($data['patient_id']);

        if ($patient->hospital_id !== $user->hospital_id) {
            return response()->json(['error' => 'Patient not found.'], 404);
        }

        // Confirm the verification log belongs to this patient and was a match
        $log = VerificationLog::findOrFail($data['verification_log_id']);

        if ($log->patient_id !== $patient->id || $log->status !== 'matched') {
            return response()->json([
                'error' => 'A successful biometric verification is required to open a visit.',
            ], 422);
        }

        // Block if patient already has an open visit
        $existing = Visit::where('patient_id', $patient->id)
            ->where('status', 'open')
            ->first();

        if ($existing) {
            return response()->json([
                'error'    => 'This patient already has an open visit.',
                'visit_id' => $existing->id,
            ], 409);
        }

        $visit = $this->visits->openVisit($patient, $user->id, $log->id);

        AuditLog::record($request, AuditLog::ACTION_VISIT_OPEN, $patient->id, null, null, [
            'visit_id' => $visit->id,
        ]);

        return response()->json(['visit' => $visit], 201);
    }

    // -------------------------------------------------------------------------
    // GET /api/visits/{visit}
    // -------------------------------------------------------------------------

    public function show(Request $request, Visit $visit): JsonResponse
    {
        $this->authorizeHospital($request, $visit);

        $visit->load([
            'patient:id,full_name,hospital_patient_id,date_of_birth,gender,phone',
            'openedBy:id,name,role',
            'closedBy:id,name,role',
            'stages.verifiedBy:id,name,role',
            'stages.supervisorOverride',
        ]);

        return response()->json(['visit' => $visit]);
    }

    // -------------------------------------------------------------------------
    // PUT /api/visits/{visit}/close
    // -------------------------------------------------------------------------

    /**
     * Close a visit (clerk checkout).
     *
     * {
     *   "verification_log_id": 789
     * }
     */
    public function close(Request $request, Visit $visit): JsonResponse
    {
        $user = $request->user();
        $this->authorizeHospital($request, $visit);

        if ($visit->isClosed()) {
            return response()->json(['error' => 'Visit is already closed.'], 409);
        }

        $data = $request->validate([
            'verification_log_id' => 'required|integer|exists:verification_logs,id',
        ]);

        $log = VerificationLog::findOrFail($data['verification_log_id']);

        if ($log->patient_id !== $visit->patient_id || $log->status !== 'matched') {
            return response()->json([
                'error' => 'A successful biometric verification is required to close the visit.',
            ], 422);
        }

        $visit = $this->visits->closeVisit($visit, $user->id, $log->id);

        AuditLog::record($request, AuditLog::ACTION_VISIT_CLOSE, $visit->patient_id, null, null, [
            'visit_id' => $visit->id,
        ]);

        return response()->json(['visit' => $visit]);
    }

    // -------------------------------------------------------------------------
    // PUT /api/visits/{visit}/reopen
    // -------------------------------------------------------------------------

    /**
     * Reopen a same-day closed visit.
     *
     * {
     *   "reason": "Patient returned — wrong medication dispensed"
     * }
     */
    public function reopen(Request $request, Visit $visit): JsonResponse
    {
        $user = $request->user();
        $this->authorizeHospital($request, $visit);

        if ($visit->isOpen()) {
            return response()->json(['error' => 'Visit is already open.'], 409);
        }

        // Same-day check — closed_at must be today
        if (! $visit->closed_at || ! $visit->closed_at->isToday()) {
            return response()->json([
                'error' => 'Only visits closed today can be reopened.',
            ], 422);
        }

        $data = $request->validate([
            'reason' => 'required|string|max:255',
        ]);

        $visit = $this->visits->reopenVisit($visit, $user->id, $data['reason']);

        AuditLog::record($request, AuditLog::ACTION_VISIT_REOPEN, $visit->patient_id, null, null, [
            'visit_id'     => $visit->id,
            'reopen_count' => $visit->reopen_count,
            'reason'       => $data['reason'],
        ]);

        return response()->json(['visit' => $visit]);
    }

    // -------------------------------------------------------------------------
    // Patient search for clerk (pre-checkin)
    // -------------------------------------------------------------------------

    /**
     * GET /api/visits/patient-search?q=BIH-2026-00142 or ?q=Mohamed
     * Used by clerk to find a patient before opening a visit.
     */
    public function patientSearch(Request $request): JsonResponse
    {
        $q        = trim($request->string('q'));
        $hospitalId = $request->user()->hospital_id;

        if (strlen($q) < 2) {
            return response()->json(['patients' => []]);
        }

        $patients = Patient::where('hospital_id', $hospitalId)
            ->where('is_active', true)
            ->where(function ($query) use ($q) {
                $query->where('hospital_patient_id', 'LIKE', strtoupper($q) . '%')
                      ->orWhere('full_name', 'LIKE', '%' . $q . '%')
                      ->orWhere('phone', 'LIKE', '%' . $q . '%');
            })
            ->select('id', 'full_name', 'hospital_patient_id', 'date_of_birth', 'gender', 'phone')
            ->limit(10)
            ->get()
            ->map(function ($patient) {
                // Flag if patient currently has an open visit
                $patient->has_open_visit = Visit::where('patient_id', $patient->id)
                    ->where('status', 'open')
                    ->exists();

                return $patient;
            });

        return response()->json(['patients' => $patients]);
    }

    // -------------------------------------------------------------------------
    // Private
    // -------------------------------------------------------------------------

    private function authorizeHospital(Request $request, Visit $visit): void
    {
        abort_if($visit->hospital_id !== $request->user()->hospital_id, 404);
    }
}
