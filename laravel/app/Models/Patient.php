<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Patient extends Model
{
    protected $fillable = [
        'hospital_id',
        'full_name',
        'date_of_birth',
        'gender',
        'jmbg',
        'phone',
        'notes',
        'is_active',
    ];

    protected $casts = [
        'date_of_birth' => 'date',
        'is_active'     => 'boolean',
    ];

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    /** All fingerprint templates enrolled for this patient. */
    public function fingerprints(): HasMany
    {
        return $this->hasMany(Fingerprint::class);
    }

    /** Active fingerprints only — used for matching. */
    public function activeFingerprints(): HasMany
    {
        return $this->hasMany(Fingerprint::class)->where('is_active', true);
    }

    public function verificationLogs(): HasMany
    {
        return $this->hasMany(VerificationLog::class);
    }

    // ------------------------------------------------------------------
    // Computed helpers
    // ------------------------------------------------------------------

    /** Returns true if at least one active fingerprint is enrolled. */
    public function isEnrolled(): bool
    {
        return $this->activeFingerprints()->exists();
    }

    /** Append is_enrolled as a virtual attribute in API responses. */
    public function toArray(): array
    {
        return array_merge(parent::toArray(), [
            'is_enrolled' => $this->isEnrolled(),
        ]);
    }
}
