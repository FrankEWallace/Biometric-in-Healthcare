<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Services\FingerprintService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PatientController extends Controller
{
    // Minimum acceptable quality score from the Python /process endpoint.
    // Scores below this indicate a blurry or poorly-positioned capture.
    private const MIN_QUALITY_SCORE = 0.30;

    public function __construct(private FingerprintService $fingerprint) {}

    /**
     * GET /api/patients?page=1&per_page=20
     */
    public function index(Request $request): JsonResponse
    {
        $patients = Patient::where('hospital_id', $request->user()->hospital_id)
            ->where('is_active', true)
            ->paginate($request->integer('per_page', 20));

        return response()->json($patients);
    }

    /**
     * POST /api/patients
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'full_name'     => 'required|string|max:200',
            'date_of_birth' => 'required|date_format:Y-m-d',
            'gender'        => 'nullable|in:male,female,other',
            'jmbg'          => 'nullable|string|size:13|unique:patients,jmbg',
            'phone'         => 'nullable|string|max:20',
            'notes'         => 'nullable|string|max:1000',
        ]);

        $patient = Patient::create(array_merge($data, [
            'hospital_id' => $request->user()->hospital_id,
        ]));

        return response()->json(['patient' => $patient], 201);
    }

    /**
     * GET /api/patients/{patient}
     */
    public function show(Request $request, Patient $patient): JsonResponse
    {
        $this->authorizeHospital($request, $patient);
        $patient->load('fingerprints:id,patient_id,finger_position,quality_score,is_primary,is_active,created_at');
        return response()->json(['patient' => $patient]);
    }

    /**
     * PUT /api/patients/{patient}
     */
    public function update(Request $request, Patient $patient): JsonResponse
    {
        $this->authorizeHospital($request, $patient);

        $data = $request->validate([
            'full_name'     => 'sometimes|string|max:200',
            'date_of_birth' => 'sometimes|date_format:Y-m-d',
            'gender'        => 'sometimes|nullable|in:male,female,other',
            'jmbg'          => 'sometimes|nullable|string|size:13|unique:patients,jmbg,' . $patient->id,
            'phone'         => 'sometimes|nullable|string|max:20',
            'notes'         => 'sometimes|nullable|string|max:1000',
        ]);

        $patient->update($data);

        return response()->json(['patient' => $patient->fresh()]);
    }

    /**
     * DELETE /api/patients/{patient} — admin only (soft-delete)
     */
    public function destroy(Request $request, Patient $patient): JsonResponse
    {
        if (! $request->user()->isAdmin()) {
            return response()->json(['error' => 'Admin role required.'], 403);
        }

        $this->authorizeHospital($request, $patient);
        $patient->update(['is_active' => false]);

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
        $this->authorizeHospital($request, $patient);

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
     * DELETE /api/patients/{patient}/fingerprints/{fingerprint}
     */
    public function removeFingerprint(Request $request, Patient $patient, Fingerprint $fingerprint): JsonResponse
    {
        $this->authorizeHospital($request, $patient);
        abort_if($fingerprint->patient_id !== $patient->id, 404);

        $fingerprint->update(['is_active' => false]);

        return response()->json(['message' => 'Fingerprint deactivated.']);
    }

    // ------------------------------------------------------------------

    private function authorizeHospital(Request $request, Patient $patient): void
    {
        abort_if(
            $patient->hospital_id !== $request->user()->hospital_id,
            404,
            'Patient not found.'
        );
    }
}
