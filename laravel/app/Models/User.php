<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = [
        'name',
        'username',
        'email',
        'password',
        'role',
        'hospital_id',
        'is_active',
        'avatar',
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

    public function isSuperAdmin(): bool
    {
        return $this->role === 'super_admin';
    }

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }

    public function isAnyAdmin(): bool
    {
        return in_array($this->role, ['super_admin', 'admin']);
    }

    public function isDoctor(): bool
    {
        return $this->role === 'doctor';
    }

    public function isNurse(): bool
    {
        return $this->role === 'nurse';
    }

    public function isClerk(): bool
    {
        return $this->role === 'clerk';
    }

    public function isLabTechnician(): bool
    {
        return $this->role === 'lab_technician';
    }

    public function isPharmacist(): bool
    {
        return $this->role === 'pharmacist';
    }

    // The stage this role is responsible for verifying at
    public function assignedStage(): ?string
    {
        return match($this->role) {
            'clerk'          => null, // clerk handles both clerk_checkin and clerk_checkout
            'nurse'          => 'triage',
            'doctor'         => 'consultation',
            'lab_technician' => 'laboratory',
            'pharmacist'     => 'pharmacy',
            default          => null,
        };
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

    public function openedVisits(): HasMany
    {
        return $this->hasMany(Visit::class, 'opened_by');
    }

    public function supervisorOverrides(): HasMany
    {
        return $this->hasMany(SupervisorOverride::class, 'supervisor_id');
    }

    public function pendingOverrideRequests(): HasMany
    {
        return $this->hasMany(SupervisorOverride::class, 'supervisor_id')
                    ->where('status', 'pending');
    }

    public function avatarUrl(): string
    {
        return $this->avatar
            ? asset('storage/' . $this->avatar)
            : 'https://ui-avatars.com/api/?name=' . urlencode($this->name) . '&background=2563eb&color=fff&size=128';
    }
}
