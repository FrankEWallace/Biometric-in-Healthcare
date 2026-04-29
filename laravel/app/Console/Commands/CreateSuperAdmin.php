<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use App\Models\Hospital;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class CreateSuperAdmin extends Command
{
    protected $signature   = 'make:super-admin';
    protected $description = 'Create a super admin account (CLI only — no UI path exists for this role)';

    public function handle(): int
    {
        $this->newLine();
        $this->line('  <fg=red;options=bold>⚠  SUPER ADMIN CREATION — RESTRICTED OPERATION</fg=red;options=bold>');
        $this->line('  This account has cross-hospital access and cannot be created through the web UI.');
        $this->line('  Ensure you are authorised to perform this action.');
        $this->newLine();

        // ── Confirmation token ────────────────────────────────────────────────
        // Forces the operator to consciously acknowledge what they are doing.
        $token = strtoupper(Str::random(6));
        $this->line("  Confirmation token: <fg=yellow;options=bold>{$token}</fg=yellow;options=bold>");
        $this->newLine();

        $entered = $this->ask('  Re-enter the confirmation token to proceed');

        if (strtoupper(trim($entered)) !== $token) {
            $this->error('  Token mismatch. Aborting.');
            return self::FAILURE;
        }

        $this->newLine();

        // ── Collect credentials ───────────────────────────────────────────────
        $name = $this->ask('  Full name');
        if (blank($name)) {
            $this->error('  Name is required.');
            return self::FAILURE;
        }

        $username = $this->ask('  Username');
        if (User::where('username', $username)->exists()) {
            $this->error("  Username '{$username}' is already taken.");
            return self::FAILURE;
        }

        $email = $this->ask('  Email');
        if (! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $this->error('  Invalid email address.');
            return self::FAILURE;
        }
        if (User::where('email', $email)->exists()) {
            $this->error("  Email '{$email}' is already registered.");
            return self::FAILURE;
        }

        $password = $this->secret('  Password (min 12 characters)');
        if (strlen($password) < 12) {
            $this->error('  Password must be at least 12 characters.');
            return self::FAILURE;
        }

        $confirm = $this->secret('  Confirm password');
        if ($password !== $confirm) {
            $this->error('  Passwords do not match.');
            return self::FAILURE;
        }

        // ── Hospital assignment (placeholder — super_admin is not scoped) ─────
        $hospitals = Hospital::where('is_active', true)->get(['id', 'name', 'city']);

        if ($hospitals->isEmpty()) {
            $this->error('  No active hospitals found. Seed hospitals first.');
            return self::FAILURE;
        }

        $this->newLine();
        $this->line('  <fg=cyan>Available hospitals (for home-base assignment):</fg=cyan>');
        foreach ($hospitals as $h) {
            $this->line("    [{$h->id}] {$h->name} — {$h->city}");
        }
        $this->newLine();

        $hospitalId = (int) $this->ask('  Enter hospital ID (used as home base only — super admin is not hospital-scoped)');

        if (! $hospitals->contains('id', $hospitalId)) {
            $this->error("  Hospital ID {$hospitalId} not found.");
            return self::FAILURE;
        }

        // ── Create ────────────────────────────────────────────────────────────
        $this->newLine();
        $this->line('  <fg=yellow>Creating super admin account…</fg=yellow>');

        $user = User::create([
            'name'        => $name,
            'username'    => $username,
            'email'       => $email,
            'password'    => Hash::make($password),
            'role'        => 'super_admin',
            'hospital_id' => $hospitalId,
            'is_active'   => true,
        ]);

        // Audit trail — no HTTP request, so we write directly
        AuditLog::create([
            'staff_id'    => $user->id,
            'hospital_id' => $hospitalId,
            'action'      => AuditLog::ACTION_USER_CREATED,
            'meta'        => [
                'created_via'       => 'artisan:make:super-admin',
                'created_user_id'   => $user->id,
                'created_user_role' => 'super_admin',
            ],
        ]);

        $this->newLine();
        $this->info("  ✓ Super admin created successfully.");
        $this->table(
            ['Field', 'Value'],
            [
                ['ID',       $user->id],
                ['Name',     $user->name],
                ['Username', $user->username],
                ['Email',    $user->email],
                ['Role',     $user->role],
            ]
        );
        $this->newLine();
        $this->line('  <fg=red>Store the password securely. It cannot be recovered.</fg=red>');
        $this->newLine();

        return self::SUCCESS;
    }
}
