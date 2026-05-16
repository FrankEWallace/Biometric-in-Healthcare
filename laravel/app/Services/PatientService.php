<?php

namespace App\Services;

use App\Models\Hospital;
use App\Models\Patient;
use Illuminate\Support\Facades\DB;

class PatientService
{
    /**
     * Register a new patient and assign a unique hospital_patient_id.
     *
     * The ID format is: {HOSPITAL_CODE}-{YEAR}-{NNNNN}
     * Example: BIH-2026-00142
     *
     * patient_seq is per-hospital per-year and incremented inside a
     * transaction to prevent race conditions under concurrent registrations.
     */
    public function register(Hospital $hospital, array $data): Patient
    {
        return DB::transaction(function () use ($hospital, $data) {
            $year = now()->year;

            $nextSeq = Patient::where('hospital_id', $hospital->id)
                ->whereYear('created_at', $year)
                ->lockForUpdate()
                ->max('patient_seq') + 1;

            $hospitalPatientId = $this->buildPatientId($hospital, $year, $nextSeq);

            return Patient::create(array_merge($data, [
                'hospital_id'         => $hospital->id,
                'patient_seq'         => $nextSeq,
                'hospital_patient_id' => $hospitalPatientId,
            ]));
        });
    }

    /**
     * Backfill hospital_patient_id for existing patients that predate this feature.
     * Safe to call multiple times — skips patients that already have an ID.
     */
    public function backfillPatientIds(Hospital $hospital): int
    {
        $filled = 0;

        Patient::where('hospital_id', $hospital->id)
            ->whereNull('hospital_patient_id')
            ->orderBy('created_at')
            ->chunk(100, function ($patients) use ($hospital, &$filled) {
                foreach ($patients as $patient) {
                    DB::transaction(function () use ($hospital, $patient, &$filled) {
                        $year    = $patient->created_at->year;
                        $nextSeq = Patient::where('hospital_id', $hospital->id)
                            ->whereYear('created_at', $year)
                            ->whereNotNull('patient_seq')
                            ->lockForUpdate()
                            ->max('patient_seq') + 1;

                        $patient->update([
                            'patient_seq'         => $nextSeq,
                            'hospital_patient_id' => $this->buildPatientId($hospital, $year, $nextSeq),
                        ]);

                        $filled++;
                    });
                }
            });

        return $filled;
    }

    /**
     * Find a patient by their human-readable ID (case-insensitive).
     * Supports partial prefix search: "BIH-2026" matches all 2026 patients.
     */
    public function findByPatientId(Hospital $hospital, string $query): ?Patient
    {
        return Patient::where('hospital_id', $hospital->id)
            ->where('hospital_patient_id', 'LIKE', strtoupper(trim($query)) . '%')
            ->first();
    }

    private function buildPatientId(Hospital $hospital, int $year, int $seq): string
    {
        $code = strtoupper($hospital->code ?? 'PAT');

        return sprintf('%s-%d-%05d', $code, $year, $seq);
    }
}
