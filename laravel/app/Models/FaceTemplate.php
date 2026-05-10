<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Crypt;

class FaceTemplate extends Model
{
    protected $fillable = [
        'patient_id',
        'hospital_id',
        'enrolled_by',
        'template',
        'quality_score',
        'is_active',
    ];

    protected $casts = [
        'quality_score' => 'float',
        'is_active'     => 'boolean',
    ];

    // ── Relationships ─────────────────────────────────────────────────────────

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    public function enrolledBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'enrolled_by');
    }

    // ── Template encryption helpers ───────────────────────────────────────────

    public function getTemplate(): ?array
    {
        if (empty($this->template)) {
            return null;
        }

        try {
            return json_decode(Crypt::decryptString($this->template), true);
        } catch (\Throwable) {
            return null;
        }
    }

    public function setTemplate(array $embedding): void
    {
        $this->template = Crypt::encryptString(json_encode($embedding));
    }
}
