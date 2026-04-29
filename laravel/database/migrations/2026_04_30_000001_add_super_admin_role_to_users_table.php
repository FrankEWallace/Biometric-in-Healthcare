<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // MySQL requires a full CHANGE to alter an enum column.
        DB::statement("
            ALTER TABLE users
            MODIFY COLUMN role ENUM('super_admin','admin','nurse','doctor')
            NOT NULL DEFAULT 'nurse'
        ");
    }

    public function down(): void
    {
        // Remove super_admin — any existing super_admin rows must be reassigned first.
        DB::statement("
            UPDATE users SET role = 'admin' WHERE role = 'super_admin'
        ");

        DB::statement("
            ALTER TABLE users
            MODIFY COLUMN role ENUM('admin','nurse','doctor')
            NOT NULL DEFAULT 'nurse'
        ");
    }
};
