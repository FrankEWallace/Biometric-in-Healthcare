<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Patient;
use App\Models\PatientEditRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PatientEditRequestController extends Controller
{
    /**
     * GET /api/edit-requests
     * Admin/super_admin: pending requests in their scope.
     */
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', PatientEditRequest::class);

        $query = PatientEditRequest::with([
            'patient:id,full_name',
            'requestedBy:id,name',
        ])->pending();

        if (! $request->user()->isSuperAdmin()) {
            $query->where('hospital_id', $request->user()->hospital_id);
        }

        return response()->json($query->orderBy('created_at')->paginate(20));
    }

    /**
     * POST /api/patients/{patient}/edit-requests
     * Nurse submits a demographic change request.
     */
    public function store(Request $request, Patient $patient): JsonResponse
    {
        $this->authorize('create', PatientEditRequest::class);
        $this->authorize('view', $patient);

        $data = $request->validate([
            'field_name' => 'required|in:full_name,phone,date_of_birth,gender',
            'new_value'  => 'required|string|max:200',
            'reason'     => 'required|string|min:10|max:500',
        ]);

        $oldValue = (string) $patient->{$data['field_name']};

        if ($oldValue === $data['new_value']) {
            return response()->json(['error' => 'New value is the same as the current value.'], 422);
        }

        // Block duplicate pending request for the same field
        $exists = PatientEditRequest::where('patient_id', $patient->id)
            ->where('field_name', $data['field_name'])
            ->pending()
            ->exists();

        if ($exists) {
            return response()->json(['error' => 'A pending request for this field already exists.'], 409);
        }

        $editRequest = PatientEditRequest::submit(
            request:  $request,
            patient:  $patient,
            field:    $data['field_name'],
            oldValue: $oldValue,
            newValue: $data['new_value'],
            reason:   $data['reason'],
        );

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_SUBMITTED, $patient->id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $data['field_name'],
        ]);

        return response()->json(['edit_request' => $editRequest], 201);
    }

    /**
     * PUT /api/edit-requests/{editRequest}/approve
     */
    public function approve(Request $request, PatientEditRequest $editRequest): JsonResponse
    {
        $this->authorize('review', $editRequest);

        if ($editRequest->status !== PatientEditRequest::STATUS_PENDING) {
            return response()->json(['error' => 'Request is no longer pending.'], 409);
        }

        if ($editRequest->expires_at->isPast()) {
            $editRequest->update(['status' => PatientEditRequest::STATUS_REJECTED]);
            return response()->json(['error' => 'Request has expired.'], 410);
        }

        $patient = $editRequest->patient;
        $patient->update([$editRequest->field_name => $editRequest->new_value]);

        $editRequest->update([
            'status'      => PatientEditRequest::STATUS_APPROVED,
            'reviewed_by' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_APPROVED, $patient->id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $editRequest->field_name,
            'old_value'       => $editRequest->old_value,
            'new_value'       => $editRequest->new_value,
        ]);

        AuditLog::record($request, AuditLog::ACTION_PATIENT_UPDATE, $patient->id, null, null, [
            'field'    => $editRequest->field_name,
            'approved_request_id' => $editRequest->id,
        ]);

        return response()->json(['message' => 'Request approved.', 'edit_request' => $editRequest->fresh()]);
    }

    /**
     * PUT /api/edit-requests/{editRequest}/reject
     */
    public function reject(Request $request, PatientEditRequest $editRequest): JsonResponse
    {
        $this->authorize('review', $editRequest);

        if ($editRequest->status !== PatientEditRequest::STATUS_PENDING) {
            return response()->json(['error' => 'Request is no longer pending.'], 409);
        }

        $editRequest->update([
            'status'      => PatientEditRequest::STATUS_REJECTED,
            'reviewed_by' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_REJECTED, $editRequest->patient_id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $editRequest->field_name,
        ]);

        return response()->json(['message' => 'Request rejected.', 'edit_request' => $editRequest->fresh()]);
    }

    /**
     * PUT /api/edit-requests/{editRequest}/cancel
     * Nurse cancels their own pending request.
     */
    public function cancel(Request $request, PatientEditRequest $editRequest): JsonResponse
    {
        $this->authorize('cancel', $editRequest);

        $editRequest->update(['status' => PatientEditRequest::STATUS_CANCELLED]);

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_CANCELLED, $editRequest->patient_id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $editRequest->field_name,
        ]);

        return response()->json(['message' => 'Request cancelled.']);
    }
}
