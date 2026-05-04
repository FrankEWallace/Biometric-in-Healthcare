<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // SQLite stores enum as plain text with no enforcement — no ALTER needed.
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("
                ALTER TABLE users
                MODIFY COLUMN role ENUM('super_admin','admin','nurse','doctor')
                NOT NULL DEFAULT 'nurse'
            ");
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("
                UPDATE users SET role = 'admin' WHERE role = 'super_admin'
            ");

            DB::statement("
                ALTER TABLE users
                MODIFY COLUMN role ENUM('admin','nurse','doctor')
                NOT NULL DEFAULT 'nurse'
            ");
        }
    }
};
