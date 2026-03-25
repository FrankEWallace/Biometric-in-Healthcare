<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, Notifiable;

    protected $fillable = [
        'name',
        'username',
        'email',
        'password',
        'role',
        'hospital_id',
        'is_active',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected $casts = [
        'is_active'         => 'boolean',
        'email_verified_at' => 'datetime',
        'password'          => 'hashed',
    ];

    // ------------------------------------------------------------------
    // Role helpers
    // ------------------------------------------------------------------

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }

    public function isOperator(): bool
    {
        return $this->role === 'operator';
    }

    public function isDoctor(): bool
    {
        return $this->role === 'doctor';
    }

    // ------------------------------------------------------------------
    // Relationships
    // ------------------------------------------------------------------

    public function hospital(): BelongsTo
    {
        return $this->belongsTo(Hospital::class);
    }

    public function verificationLogs(): HasMany
    {
        return $this->hasMany(VerificationLog::class, 'operator_id');
    }
}
