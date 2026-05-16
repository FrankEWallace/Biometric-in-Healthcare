<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Hospital extends Model
{
    use HasFactory;
    protected $fillable = [
        'name',
        'code',
        'city',
        'wifi_ssid',
        'gps_latitude',
        'gps_longitude',
        'gps_radius_meters',
        'is_active',
        'face_recognition_enabled',
    ];

    protected $casts = [
        'gps_latitude'             => 'decimal:7',
        'gps_longitude'            => 'decimal:7',
        'gps_radius_meters'        => 'integer',
        'face_recognition_enabled' => 'boolean',
    ];

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function patients(): HasMany
    {
        return $this->hasMany(Patient::class);
    }

    public function verificationLogs(): HasMany
    {
        return $this->hasMany(VerificationLog::class);
    }

    public function visits(): HasMany
    {
        return $this->hasMany(Visit::class);
    }

    public function activeVisits(): HasMany
    {
        return $this->hasMany(Visit::class)->where('status', 'open');
    }
}
