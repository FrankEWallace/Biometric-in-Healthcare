<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupervisorOverride extends Model
{
    protected $fillable = [
        'visit_stage_id',
        'requested_by',
        'supervisor_id',
        'status',
        'fallback_chain',
        'staff_note',
        'supervisor_note',
        'requested_at',
        'resolved_at',
    ];

    protected $casts = [
        'requested_at' => 'datetime',
        'resolved_at'  => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

    public function visitStage(): BelongsTo
    {
        return $this->belongsTo(VisitStage::class);
    }

    public function requestedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by');
    }

    public function supervisor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'supervisor_id');
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function isApproved(): bool
    {
        return $this->status === 'approved';
    }

    public function isDenied(): bool
    {
        return $this->status === 'denied';
    }

    public function resolve(User $supervisor, string $decision, ?string $note = null): void
    {
        $this->update([
            'supervisor_id'   => $supervisor->id,
            'status'          => $decision, // 'approved' or 'denied'
            'supervisor_note' => $note,
            'resolved_at'     => now(),
        ]);
    }
}
