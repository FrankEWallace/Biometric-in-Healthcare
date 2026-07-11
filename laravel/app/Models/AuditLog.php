<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AuditLog extends Model
{
    public const UPDATED_AT = null; // audit rows are immutable

    // Action constants — match the DB enum exactly
    public const ACTION_EHR_ACCESS              = 'ehr_access';
    public const ACTION_INSURANCE_CHECK         = 'insurance_check';
    public const ACTION_FINGERPRINT_MATCH       = 'fingerprint_match';
    public const ACTION_FINGERPRINT_NO_MATCH    = 'fingerprint_no_match';
    public const ACTION_PATIENT_CREATE          = 'patient_create';
    public const ACTION_PATIENT_UPDATE          = 'patient_update';
    public const ACTION_PATIENT_DELETE          = 'patient_delete';
    public const ACTION_FINGERPRINT_ENROLL      = 'fingerprint_enroll';
    public const ACTION_FINGERPRINT_DELETE      = 'fingerprint_delete';
    public const ACTION_MANUAL_OVERRIDE         = 'manual_override';
    public const ACTION_FINGERPRINT_LOCK        = 'fingerprint_lock';
    public const ACTION_FINGERPRINT_UNLOCK      = 'fingerprint_unlock';
    public const ACTION_EDIT_REQUEST_SUBMITTED  = 'edit_request_submitted';
    public const ACTION_EDIT_REQUEST_APPROVED   = 'edit_request_approved';
    public const ACTION_EDIT_REQUEST_REJECTED   = 'edit_request_rejected';
    public const ACTION_EDIT_REQUEST_CANCELLED  = 'edit_request_cancelled';
    public const ACTION_LOGIN_SUCCESS           = 'login_success';
    public const ACTION_LOGIN_FAILED            = 'login_failed';
    public const ACTION_USER_CREATED            = 'user_created';
    public const ACTION_USER_UPDATED            = 'user_updated';
    public const ACTION_USER_DEACTIVATED        = 'user_deactivated';
    public const ACTION_HOSPITAL_CREATED        = 'hospital_created';
    public const ACTION_HOSPITAL_UPDATED        = 'hospital_updated';
    public const ACTION_HOSPITAL_DEACTIVATED    = 'hospital_deactivated';
    public const ACTION_FACE_ENROLL                = 'face_enroll';
    public const ACTION_FACE_MATCH                 = 'face_match';
    public const ACTION_FACE_NO_MATCH              = 'face_no_match';
    public const ACTION_FACE_MANUAL_CONFIRM        = 'face_manual_confirm';
    public const ACTION_VISIT_OPEN                 = 'visit_open';
    public const ACTION_VISIT_CLOSE                = 'visit_close';
    public const ACTION_VISIT_REOPEN               = 'visit_reopen';
    public const ACTION_STAGE_VERIFIED             = 'stage_verified';
    public const ACTION_STAGE_OVERRIDE_REQUESTED   = 'stage_override_requested';
    public const ACTION_STAGE_OVERRIDE_RESOLVED    = 'stage_override_resolved';
    public const ACTION_ACCESS_RESTRICTED          = 'access_restricted';

    protected $fillable = [
        'staff_id',
        'patient_id',
        'hospital_id',
        'action',
        'homis_module',
        'response_status',
        'ip_address',
        'user_agent',
        'meta',
    ];

    protected $casts = [
        'meta'       => 'array',
        'created_at' => 'datetime',
    ];

    // ── Relationships ─────────────────────────────────────────────────────────

    public function staff(): BelongsTo
    {
        return $this->belongsTo(User::class, 'staff_id');
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    // ── Factory helper ────────────────────────────────────────────────────────

    /**
     * Write an audit entry from a request context.
     */
    public static function record(
        \Illuminate\Http\Request $request,
        string  $action,
        ?int    $patientId    = null,
        ?string $homisModule  = null,
        ?string $responseStatus = null,
        array   $meta         = [],
    ): self {
        return self::create([
            'staff_id'        => $request->user()->id,
            'patient_id'      => $patientId,
            'hospital_id'     => $request->user()->hospital_id,
            'action'          => $action,
            'homis_module'    => $homisModule,
            'response_status' => $responseStatus,
            'ip_address'      => $request->ip(),
            'user_agent'      => $request->userAgent(),
            'meta'            => $meta ?: null,
        ]);
    }
}
