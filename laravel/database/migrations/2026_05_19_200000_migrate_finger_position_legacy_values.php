<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Migrate legacy finger_position values created before the per-digit enum was
 * introduced.  Old enrollments used 'right_hand' and 'left_hand' as position
 * labels.  Map them to specific digits so verification logic is unambiguous.
 *
 *   right_hand → right_index
 *   left_hand  → left_index
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('fingerprints')
            ->where('finger_position', 'right_hand')
            ->update(['finger_position' => 'right_index']);

        DB::table('fingerprints')
            ->where('finger_position', 'left_hand')
            ->update(['finger_position' => 'left_index']);
    }

    public function down(): void
    {
        // No reverse — the original values were ambiguous; reverting would lose information.
    }
};
