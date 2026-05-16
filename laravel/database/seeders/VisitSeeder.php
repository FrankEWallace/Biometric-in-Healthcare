<?php

namespace Database\Seeders;

use App\Models\Hospital;
use App\Models\Patient;
use App\Models\User;
use App\Models\Visit;
use App\Models\VisitStage;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;

class VisitSeeder extends Seeder
{
    /**
     * Seeds three demo visits for Sarajevo:
     *  1. Amira Kovačević — fully completed (closed, shows in history)
     *  2. Nedim Husić     — at Consultation (3 stages done, mid-journey)
     *  3. Fatima Softić   — at Triage (1 stage done, just checked in)
     */
    public function run(): void
    {
        $sarajevo = Hospital::where('city', 'Sarajevo')->first();
        $clerk    = User::where('username', 'amina.clerk')->first();
        $nurse    = User::where('username', 'editha.deo')->first();
        $doctor   = User::where('username', 'dr.joseph')->first();
        $lab      = User::where('username', 'said.lab')->first();
        $pharma   = User::where('username', 'fatima.pharma')->first();

        $amira  = Patient::where('nida', '1407985175038')->first();
        $nedim  = Patient::where('nida', '2203990175012')->first();
        $fatima = Patient::where('nida', '0511975175021')->first();

        if (!$sarajevo || !$clerk || !$amira || !$nedim || !$fatima) {
            $this->command->warn('VisitSeeder: required hospitals/users/patients not found. Run HospitalSeeder, UserSeeder, PatientSeeder first.');
            return;
        }

        $today = Carbon::today();

        // ── 1. Completed visit (Amira — closed, for history demo) ─────────────
        if (! Visit::where('patient_id', $amira->id)->where('status', 'closed')->whereDate('opened_at', $today)->exists()) {
            $v1 = Visit::create([
                'hospital_id' => $sarajevo->id,
                'patient_id'  => $amira->id,
                'opened_by'   => $clerk->id,
                'closed_by'   => $clerk->id,
                'visit_type'  => 'opd',
                'status'      => 'closed',
                'opened_at'   => $today->copy()->setTime(8, 0),
                'closed_at'   => $today->copy()->setTime(11, 30),
                'reopen_count'=> 0,
            ]);

            $this->createStages($v1, [
                'clerk_checkin'  => [$clerk,  $today->copy()->setTime(8,  0),  []],
                'triage'         => [$nurse,  $today->copy()->setTime(8, 20),  ['bp' => '120/80', 'pulse' => 72, 'temp' => 36.6, 'weight' => 62, 'visit_type_set' => 'opd']],
                'consultation'   => [$doctor, $today->copy()->setTime(9, 10),  ['diagnosis' => 'Upper respiratory infection', 'notes' => 'Rest and fluids recommended.', 'prescriptions' => [['name' => 'Amoxicillin', 'dosage' => '500mg 3×/day']]]],
                'laboratory'     => [$lab,    $today->copy()->setTime(10, 0),  ['tests' => [['name' => 'CBC', 'value' => 'WBC 8.2', 'result' => 'normal'], ['name' => 'CRP', 'value' => '12 mg/L', 'result' => 'elevated']]]],
                'pharmacy'       => [$pharma, $today->copy()->setTime(11, 0),  ['medications' => [['name' => 'Amoxicillin', 'dosage' => '500mg', 'dispensed' => true]]]],
                'clerk_checkout' => [$clerk,  $today->copy()->setTime(11, 30), []],
            ]);
        }

        // ── 2. Mid-journey visit (Nedim — at Consultation) ───────────────────
        if (! Visit::where('patient_id', $nedim->id)->where('status', 'open')->exists()) {
            $v2 = Visit::create([
                'hospital_id' => $sarajevo->id,
                'patient_id'  => $nedim->id,
                'opened_by'   => $clerk->id,
                'visit_type'  => 'opd',
                'status'      => 'open',
                'opened_at'   => $today->copy()->setTime(9, 0),
                'reopen_count'=> 0,
            ]);

            $this->createStages($v2, [
                'clerk_checkin' => [$clerk, $today->copy()->setTime(9,  0), []],
                'triage'        => [$nurse, $today->copy()->setTime(9, 25), ['bp' => '135/88', 'pulse' => 80, 'temp' => 37.1, 'weight' => 85, 'visit_type_set' => 'opd']],
            ]);
        }

        // ── 3. Early visit (Fatima — just checked in, at Triage) ─────────────
        if (! Visit::where('patient_id', $fatima->id)->where('status', 'open')->exists()) {
            $v3 = Visit::create([
                'hospital_id' => $sarajevo->id,
                'patient_id'  => $fatima->id,
                'opened_by'   => $clerk->id,
                'visit_type'  => 'pending',
                'status'      => 'open',
                'opened_at'   => $today->copy()->setTime(10, 30),
                'reopen_count'=> 0,
            ]);

            $this->createStages($v3, [
                'clerk_checkin' => [$clerk, $today->copy()->setTime(10, 30), []],
            ]);
        }
    }

    /**
     * Create all 6 stage rows for a visit.
     * $completedStages: ['stage_name' => [$user, $verifiedAt, $simulatedData]]
     */
    private function createStages(Visit $visit, array $completedStages): void
    {
        $allStages = [
            'clerk_checkin', 'triage', 'consultation',
            'laboratory', 'pharmacy', 'clerk_checkout',
        ];

        foreach ($allStages as $stage) {
            if (isset($completedStages[$stage])) {
                [$user, $verifiedAt, $simData] = $completedStages[$stage];
                VisitStage::create([
                    'visit_id'        => $visit->id,
                    'stage'           => $stage,
                    'status'          => 'completed',
                    'verified_by'     => $user->id,
                    'verified_at'     => $verifiedAt,
                    'simulated_data'  => empty($simData) ? null : $simData,
                ]);
            } else {
                VisitStage::firstOrCreate(
                    ['visit_id' => $visit->id, 'stage' => $stage],
                    ['status' => 'pending'],
                );
            }
        }
    }
}
