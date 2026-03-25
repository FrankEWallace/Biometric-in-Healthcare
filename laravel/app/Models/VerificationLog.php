<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VerificationLog extends Model
{
    protected $fillable = [
        'patient_id',
        'fingerprint_id',
        'operator_id',
        'hospital_id',
        'score',
        'status',
        'gps_latitude',
        'gps_longitude',
        'wifi_ssid',
        'error_message',
    ];

    protected $casts = [
        'score'         => 'float',
        'gps_latitude'  => 'decimal:7',
        'gps_longitude' => 'decimal:7',
        'created_at'    => 'datetime',
    ];

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function fingerprint(): BelongsTo
    {
        return $this->belongsTo(Fingerprint::class);
    }

    public function operator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'operator_id');
    }

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    public function isMatched(): bool
    {
        return $this->status === 'matched';
    }
}
