<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Services\FingerprintService;
use App\Services\PatientService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PatientController extends Controller
{
    // Minimum acceptable quality score from the Python /process endpoint.
    // Scores below this indicate a blurry or poorly-positioned capture.
    private const MIN_QUALITY_SCORE = 0.30;

    // Minimum usable fingers required for a four-finger hand enrollment.
    // Mirrors the matcher's min_fingers fusion guard (3 of 4).
    private const MIN_HAND_FINGERS = 3;

    public function __construct(
        private FingerprintService $fingerprint,
        private PatientService     $patientService,
    ) {}

    /**
     * GET /api/patients?search=Ali&page=1&per_page=20
     *
     * Optional ?search= matches full_name, hospital_patient_id, or nida
     * (prefix match, case-insensitive). Returns at most per_page results.
     */
    public function index(Request $request): JsonResponse
    {
        $query = Patient::where('hospital_id', $request->user()->hospital_id)
            ->where('is_active', true);

        if ($search = trim((string) $request->query('search', ''))) {
            $like = $search . '%';
            $query->where(function ($q) use ($like) {
                $q->where('full_name', 'like', $like)
                  ->orWhere('hospital_patient_id', 'like', $like)
                  ->orWhere('nida', 'like', $like);
            });
        }

        $patients = $query->orderBy('full_name')
            ->paginate($request->integer('per_page', 20));

        return response()->json($patients);
    }

    /**
     * POST /api/patients
     */
    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Patient::class);

        $data = $request->validate([
            'full_name'     => 'required|string|max:200',
            'date_of_birth' => 'required|date_format:Y-m-d',
            'gender'        => 'nullable|in:male,female,other',
            'nida'          => 'nullable|string|size:20|unique:patients,nida',
            'phone'         => 'nullable|string|max:20',
            'notes'         => 'nullable|string|max:1000',
        ]);

        $hospital = $request->user()->hospital;
        $patient  = $this->patientService->register($hospital, $data);

        AuditLog::record($request, AuditLog::ACTION_PATIENT_CREATE, $patient->id);

        return response()->json(['patient' => $patient], 201);
    }

    /**
     * GET /api/patients/{patient}
     */
    public function show(Request $request, Patient $patient): JsonResponse
    {
        $this->authorize('view', $patient);
        $patient->load('fingerprints:id,patient_id,finger_position,quality_score,is_primary,is_active,created_at');
        return response()->json(['patient' => $patient]);
    }

    /**
     * PUT /api/patients/{patient}
     * Admin/super_admin only. Nurses must use POST /patients/{patient}/edit-requests.
     */
    public function update(Request $request, Patient $patient): JsonResponse
    {
        if ($request->user()->isNurse()) {
            return response()->json([
                'error' => 'Nurses cannot edit patient data directly. Submit an edit request instead.',
                'hint'  => 'POST /api/patients/' . $patient->id . '/edit-requests',
            ], 403);
        }

        $this->authorize('update', $patient);

        $data = $request->validate([
            'full_name'     => 'sometimes|string|max:200',
            'date_of_birth' => 'sometimes|date_format:Y-m-d',
            'gender'        => 'sometimes|nullable|in:male,female,other',
            'nida'          => 'sometimes|nullable|string|size:20|unique:patients,nida,' . $patient->id,
            'phone'         => 'sometimes|nullable|string|max:20',
            'notes'         => 'sometimes|nullable|string|max:1000',
        ]);

        $patient->update($data);

        AuditLog::record($request, AuditLog::ACTION_PATIENT_UPDATE, $patient->id, null, null, [
            'fields_changed' => array_keys($data),
        ]);

        return response()->json(['patient' => $patient->fresh()]);
    }

    /**
     * DELETE /api/patients/{patient} — admin/super_admin only (soft-delete)
     */
    public function destroy(Request $request, Patient $patient): JsonResponse
    {
        $this->authorize('delete', $patient);

        $patient->update(['is_active' => false]);

        AuditLog::record($request, AuditLog::ACTION_PATIENT_DELETE, $patient->id);

        return response()->json(['message' => 'Patient deactivated.']);
    }

    /**
     * POST /api/patients/{patient}/enroll
     * {
     *   "image":            "<base64>",
     *   "finger_position":  "right_index",   // optional
     *   "is_primary":       true             // optional
     * }
     *
     * Rejects the image if quality_score < MIN_QUALITY_SCORE so that only
     * reliable templates enter the matching pool.
     */
    public function enroll(Request $request, Patient $patient): JsonResponse
    {
        $this->authorize('enroll', $patient);

        $data = $request->validate([
            'image'           => 'required|string',
            'finger_position' => [
                'nullable',
                'in:right_thumb,right_index,right_middle,right_ring,right_little,'
                  . 'left_thumb,left_index,left_middle,left_ring,left_little',
            ],
            'is_primary' => 'nullable|boolean',
        ]);

        $fingerPosition = $data['finger_position'] ?? 'right_index';
        $isPrimary      = (bool) ($data['is_primary'] ?? false);

        // ------------------------------------------------------------------
        // 1. Extract template + quality score via Python service
        // ------------------------------------------------------------------
        $result       = $this->fingerprint->process($data['image']);
        $qualityScore = (float) ($result['quality_score'] ?? 0.0);

        // ------------------------------------------------------------------
        // 2. Quality gate — reject poor captures before storing anything
        // ------------------------------------------------------------------
        if ($qualityScore < self::MIN_QUALITY_SCORE) {
            return response()->json([
                'error'         => 'Fingerprint quality is too low. Please recapture.',
                'quality_score' => $qualityScore,
                'minimum'       => self::MIN_QUALITY_SCORE,
            ], 422);
        }

        // ------------------------------------------------------------------
        // 3. If marking primary, demote any existing primary for this patient
        // ------------------------------------------------------------------
        if ($isPrimary) {
            Fingerprint::where('patient_id', $patient->id)
                ->where('is_primary', true)
                ->update(['is_primary' => false]);
        }

        // ------------------------------------------------------------------
        // 4. Upsert — re-enrolling the same finger overwrites the old template
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

        AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_ENROLL, $patient->id, null, null, [
            'fingerprint_id'  => $fp->id,
            'finger_position' => $fp->finger_position,
            'quality_score'   => $fp->quality_score,
        ]);

        return response()->json([
            'message'         => 'Fingerprint enrolled successfully.',
            'fingerprint_id'  => $fp->id,
            'patient_id'      => $patient->id,
            'finger_position' => $fp->finger_position,
            'quality_score'   => $fp->quality_score,
            'is_primary'      => $fp->is_primary,
        ], 201);
    }

    /**
     * POST /api/patients/{patient}/enroll-hand
     *
     * Four-finger ("hand slap") enrollment. The nurse photographs a hand; the
     * Python service segments it into four finger crops and returns one template
     * per finger. Each finger is stored as its own {@see Fingerprint} row (the
     * finger_position enum already covers all four), so the existing 1:1, 1:N,
     * and multimodal flows keep working per-finger while verify-hand fuses them.
     *
     * At least {@see self::MIN_HAND_FINGERS} fingers must pass the quality gate;
     * low-quality fingers are skipped (logged), not stored. The whole set is
     * written in one transaction so a partial hand never persists.
     *
     * Fields:
     *   image      (string, required) — base64 whole-hand photo
     *   hand       (string)           — "right" | "left" (default right)
     *   is_primary (bool)             — mark the index finger primary for 1:N pass-1
     */
    public function enrollHand(Request $request, Patient $patient): JsonResponse
    {
        $this->authorize('enroll', $patient);

        $data = $request->validate([
            'image'      => 'required|string',
            'hand'       => 'nullable|in:right,left',
            'is_primary' => 'nullable|boolean',
        ]);

        $hand      = $data['hand'] ?? 'right';
        $isPrimary = (bool) ($data['is_primary'] ?? false);

        // 1. Segment + extract 4 templates via the Python service (contactless).
        $result  = $this->fingerprint->processHand($data['image'], $hand, 'contactless');
        $fingers = $result['fingers'] ?? [];

        // 2. Quality gate per finger — keep only usable fingers.
        $usable = array_values(array_filter(
            $fingers,
            fn ($f) => (float) ($f['quality_score'] ?? 0.0) >= self::MIN_QUALITY_SCORE
        ));

        if (count($usable) < self::MIN_HAND_FINGERS) {
            return response()->json([
                'error'          => 'Too few usable fingers. Please retake with the hand flat and in focus.',
                'usable_fingers' => count($usable),
                'required'       => self::MIN_HAND_FINGERS,
                'minimum'        => self::MIN_QUALITY_SCORE,
            ], 422);
        }

        // 3. The index finger is the primary/gallery representative for this hand.
        $indexPosition = $hand === 'left' ? 'left_index' : 'right_index';

        $stored = DB::transaction(function () use ($request, $patient, $usable, $isPrimary, $indexPosition) {
            if ($isPrimary) {
                Fingerprint::where('patient_id', $patient->id)
                    ->where('is_primary', true)
                    ->update(['is_primary' => false]);
            }

            $rows = [];
            foreach ($usable as $finger) {
                $position = $finger['finger_position'];

                $fp = Fingerprint::firstOrNew([
                    'patient_id'      => $patient->id,
                    'finger_position' => $position,
                ]);

                $fp->hospital_id   = $patient->hospital_id;
                $fp->enrolled_by   = $request->user()->id;
                $fp->quality_score = (float) ($finger['quality_score'] ?? 0.0);
                $fp->is_primary    = $isPrimary && $position === $indexPosition;
                $fp->is_active     = true;
                $fp->setTemplate($finger['template']);
                $fp->save();

                $rows[] = $fp;
            }

            return $rows;
        });

        AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_ENROLL, $patient->id, null, null, [
            'hand'             => $hand,
            'fingers_enrolled' => array_map(fn ($fp) => $fp->finger_position, $stored),
            'matcher'          => $result['matcher'] ?? null,
        ]);

        return response()->json([
            'message'    => 'Hand enrolled successfully.',
            'patient_id' => $patient->id,
            'hand'       => $hand,
            'matcher'    => $result['matcher'] ?? null,
            'fingers'    => array_map(fn ($fp) => [
                'fingerprint_id'  => $fp->id,
                'finger_position' => $fp->finger_position,
                'quality_score'   => $fp->quality_score,
                'is_primary'      => $fp->is_primary,
            ], $stored),
        ], 201);
    }

    /**
     * DELETE /api/patients/{patient}/fingerprints/{fingerprint}
     * Admin/super_admin only.
     */
    public function removeFingerprint(Request $request, Patient $patient, Fingerprint $fingerprint): JsonResponse
    {
        $this->authorize('removeFingerprint', $patient);
        abort_if($fingerprint->patient_id !== $patient->id, 404);

        $fingerprint->update(['is_active' => false]);

        AuditLog::record($request, AuditLog::ACTION_FINGERPRINT_DELETE, $patient->id, null, null, [
            'fingerprint_id'  => $fingerprint->id,
            'finger_position' => $fingerprint->finger_position,
        ]);

        return response()->json(['message' => 'Fingerprint deactivated.']);
    }
}
