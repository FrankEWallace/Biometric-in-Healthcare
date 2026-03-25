<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Hospital extends Model
{
    protected $fillable = [
        'name',
        'city',
        'wifi_ssid',
        'gps_latitude',
        'gps_longitude',
        'gps_radius_meters',
        'is_active',
    ];

    protected $casts = [
        'gps_latitude'       => 'decimal:7',
        'gps_longitude'      => 'decimal:7',
        'gps_radius_meters'  => 'integer',
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
}
