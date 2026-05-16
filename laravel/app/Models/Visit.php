<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Visit extends Model
{
    protected $fillable = [
        'hospital_id',
        'patient_id',
        'opened_by',
        'closed_by',
        'visit_type',
        'status',
        'opened_at',
        'closed_at',
        'reopen_count',
        'reopen_reason',
    ];

    protected $casts = [
        'opened_at'    => 'datetime',
        'closed_at'    => 'datetime',
        'reopen_count' => 'integer',
    ];

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function openedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'opened_by');
    }

    public function closedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    public function stages(): HasMany
    {
        return $this->hasMany(VisitStage::class);
    }

    public function completedStages(): HasMany
    {
        return $this->hasMany(VisitStage::class)->where('status', 'completed');
    }

    public function stage(string $stageName): HasOne
    {
        return $this->hasOne(VisitStage::class)->where('stage', $stageName);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    public function isOpen(): bool
    {
        return $this->status === 'open';
    }

    public function isClosed(): bool
    {
        return $this->status === 'closed';
    }

    public function isOpd(): bool
    {
        return $this->visit_type === 'opd';
    }

    public function isIpd(): bool
    {
        return $this->visit_type === 'ipd';
    }

    public function isPending(): bool
    {
        return $this->visit_type === 'pending';
    }

    // Returns ordered stage timeline for the visit summary screen
    public function stageTimeline(): array
    {
        $order = [
            'clerk_checkin',
            'triage',
            'consultation',
            'laboratory',
            'pharmacy',
            'clerk_checkout',
        ];

        $stages = $this->stages()->with('verifiedBy')->get()->keyBy('stage');

        return collect($order)->map(fn($name) => $stages->get($name))->filter()->values()->toArray();
    }
}
