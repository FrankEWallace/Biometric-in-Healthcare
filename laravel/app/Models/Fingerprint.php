<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Crypt;

class Fingerprint extends Model
{
    protected $fillable = [
        'patient_id',
        'hospital_id',
        'enrolled_by',
        'finger_position',
        'template',
        'quality_score',
        'is_primary',
        'is_active',
    ];

    protected $casts = [
        'quality_score' => 'float',
        'is_primary'    => 'boolean',
        'is_active'     => 'boolean',
    ];

    // Never expose the encrypted blob in JSON responses
    protected $hidden = ['template'];

    // ------------------------------------------------------------------
    // Encryption helpers
    // ------------------------------------------------------------------

    public function setTemplate(array $template): void
    {
        $this->template = Crypt::encryptString(json_encode($template));
    }

    public function getTemplate(): ?array
    {
        if (empty($this->template)) {
            return null;
        }
        return json_decode(Crypt::decryptString($this->template), true);
    }

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

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
}
