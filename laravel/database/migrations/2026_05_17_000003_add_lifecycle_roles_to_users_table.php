<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("
                ALTER TABLE users
                MODIFY COLUMN role ENUM('super_admin','admin','clerk','nurse','doctor','lab_technician','pharmacist')
                NOT NULL DEFAULT 'nurse'
            ");
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement("
                UPDATE users SET role = 'nurse'
                WHERE role IN ('clerk','lab_technician','pharmacist')
            ");

            DB::statement("
                ALTER TABLE users
                MODIFY COLUMN role ENUM('super_admin','admin','nurse','doctor')
                NOT NULL DEFAULT 'nurse'
            ");
        }
    }
};
