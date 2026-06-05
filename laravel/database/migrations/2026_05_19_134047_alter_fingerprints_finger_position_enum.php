<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }

        DB::statement("ALTER TABLE fingerprints MODIFY COLUMN finger_position ENUM(
            'right_thumb','right_index','right_middle','right_ring','right_little',
            'left_thumb','left_index','left_middle','left_ring','left_little',
            'right_hand','left_hand'
        ) NOT NULL DEFAULT 'right_index'");
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            return;
        }

        DB::statement("ALTER TABLE fingerprints MODIFY COLUMN finger_position ENUM(
            'right_thumb','right_index','right_middle','right_ring','right_little',
            'left_thumb','left_index','left_middle','left_ring','left_little'
        ) NOT NULL DEFAULT 'right_index'");
    }
};
