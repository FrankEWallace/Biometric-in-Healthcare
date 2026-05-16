<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class VisitStage extends Model
{
    protected $fillable = [
        'visit_id',
        'stage',
        'status',
        'verified_by',
        'verification_log_id',
        'verified_at',
        'simulated_data',
    ];

    protected $casts = [
        'verified_at'    => 'datetime',
        'simulated_data' => 'array',
    ];

    // Stages mapped to the roles responsible for them
    public const STAGE_ROLES = [
        'clerk_checkin'  => ['clerk'],
        'triage'         => ['nurse'],
        'consultation'   => ['doctor'],
        'laboratory'     => ['lab_technician'],
        'pharmacy'       => ['pharmacist'],
        'clerk_checkout' => ['clerk'],
    ];

    // Default simulated data templates per stage
    public const SIMULATED_DEFAULTS = [
        'triage' => [
            'bp'             => '120/80',
            'pulse'          => 78,
            'temp'           => 36.7,
            'weight'         => 70,
            'visit_type_set' => null,
        ],
        'consultation' => [
            'diagnosis'     => 'Acute upper respiratory tract infection',
            'notes'         => 'Patient presents with mild fever and sore throat. No signs of lower respiratory involvement.',
            'lab_orders'    => ['Full Blood Count', 'CRP'],
            'prescriptions' => [
                ['name' => 'Paracetamol 500mg', 'dosage' => 'Every 8 hours for 3 days'],
                ['name' => 'Amoxicillin 500mg', 'dosage' => 'Every 12 hours for 5 days'],
            ],
        ],
        'laboratory' => [
            'tests' => [
                ['name' => 'Full Blood Count', 'result' => 'normal',   'value' => 'WBC 7.2, RBC 4.8, Hb 13.5'],
                ['name' => 'CRP',              'result' => 'elevated', 'value' => '18 mg/L'],
            ],
        ],
        'pharmacy' => [
            'medications' => [
                ['name' => 'Paracetamol 500mg', 'dosage' => 'Every 8 hours for 3 days',  'dispensed' => true],
                ['name' => 'Amoxicillin 500mg', 'dosage' => 'Every 12 hours for 5 days', 'dispensed' => true],
            ],
        ],
    ];

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

    public function visit(): BelongsTo
    {
        return $this->belongsTo(Visit::class);
    }

    public function verifiedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'verified_by');
    }

    public function verificationLog(): BelongsTo
    {
        return $this->belongsTo(VerificationLog::class);
    }

    public function supervisorOverride(): HasOne
    {
        return $this->hasOne(SupervisorOverride::class);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    public function isCompleted(): bool
    {
        return $this->status === 'completed';
    }

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function hasPendingOverride(): bool
    {
        return $this->supervisorOverride()->where('status', 'pending')->exists();
    }

    public function allowedRoles(): array
    {
        return self::STAGE_ROLES[$this->stage] ?? [];
    }
}
