<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Crypt;

class Fingerprint extends Model
{
    use HasFactory;
    public const LOCK_THRESHOLD = 10; // failures within the window before locking
    public const LOCK_WINDOW_HOURS = 1; // rolling window in hours

    protected $fillable = [
        'patient_id',
        'hospital_id',
        'enrolled_by',
        'finger_position',
        'template',
        'template_format',
        'quality_score',
        'is_primary',
        'is_gallery_lead',
        'needs_reenrollment',
        'is_active',
        'failed_attempts',
        'locked_at',
        'attempts_window_start',
    ];

    protected $casts = [
        'quality_score'         => 'float',
        'is_primary'            => 'boolean',
        'is_gallery_lead'       => 'boolean',
        'needs_reenrollment'    => 'boolean',
        'is_active'             => 'boolean',
        'locked_at'             => 'datetime',
        'attempts_window_start' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Lock helpers
    // ------------------------------------------------------------------

    public function isLocked(): bool
    {
        return $this->locked_at !== null;
    }

    /**
     * Record a failed verification attempt.
     * Resets the window if the last attempt was outside the rolling window.
     * Locks the fingerprint when failed_attempts reaches LOCK_THRESHOLD.
     *
     * @return bool  true if the fingerprint just became locked
     */
    public function recordFailure(): bool
    {
        $now = now();
        $windowExpired = $this->attempts_window_start === null
            || $this->attempts_window_start->lt($now->copy()->subHours(self::LOCK_WINDOW_HOURS));

        if ($windowExpired) {
            // Start a fresh window
            $this->failed_attempts        = 1;
            $this->attempts_window_start  = $now;
        } else {
            $this->failed_attempts++;
        }

        $justLocked = false;

        if ($this->failed_attempts >= self::LOCK_THRESHOLD && ! $this->isLocked()) {
            $this->locked_at = $now;
            $justLocked      = true;
        }

        $this->save();

        return $justLocked;
    }

    /**
     * Clear all lock and failure state.
     */
    public function unlock(): void
    {
        $this->failed_attempts        = 0;
        $this->locked_at              = null;
        $this->attempts_window_start  = null;
        $this->save();
    }

    // Never expose the encrypted blob in JSON responses
    protected $hidden = ['template'];

    // ------------------------------------------------------------------
    // Encryption helpers
    // ------------------------------------------------------------------

    public function setTemplate(array $template): void
    {
        $this->template        = Crypt::encryptString(json_encode($template));
        $this->template_format = $template['format'] ?? 'sourceafis_v1';
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
