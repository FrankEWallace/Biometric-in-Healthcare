<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PatientEditRequest extends Model
{
    public const UPDATED_AT = null;

    public const STATUS_PENDING   = 'pending';
    public const STATUS_APPROVED  = 'approved';
    public const STATUS_REJECTED  = 'rejected';
    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'patient_id',
        'requested_by',
        'reviewed_by',
        'hospital_id',
        'field_name',
        'old_value',
        'new_value',
        'reason',
        'status',
        'reviewed_at',
        'expires_at',
    ];

    protected $casts = [
        'reviewed_at' => 'datetime',
        'expires_at'  => 'datetime',
        'created_at'  => 'datetime',
    ];

    // ── Relationships ─────────────────────────────────────────────────────────

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function requestedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by');
    }

    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    // ── Scopes ────────────────────────────────────────────────────────────────

    public function scopePending($query)
    {
        return $query->where('status', self::STATUS_PENDING)
                     ->where('expires_at', '>', now());
    }

    // ── Factory helper ────────────────────────────────────────────────────────

    public static function submit(
        \Illuminate\Http\Request $request,
        Patient $patient,
        string $field,
        string $oldValue,
        string $newValue,
        string $reason,
    ): self {
        return self::create([
            'patient_id'   => $patient->id,
            'requested_by' => $request->user()->id,
            'hospital_id'  => $request->user()->hospital_id,
            'field_name'   => $field,
            'old_value'    => $oldValue,
            'new_value'    => $newValue,
            'reason'       => $reason,
            'status'       => self::STATUS_PENDING,
            'expires_at'   => now()->addDays(30),
        ]);
    }
}
