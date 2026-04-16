<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AuditLog extends Model
{
    public const UPDATED_AT = null; // audit rows are immutable

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
