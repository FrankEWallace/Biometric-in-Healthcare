<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE patients RENAME COLUMN jmbg TO nida');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE patients RENAME COLUMN nida TO jmbg');
    }
};
