<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\Fingerprint;
use App\Models\Patient;
use App\Models\User;
use App\Models\VerificationLog;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

class DashboardController extends Controller
{
    public function index(): View
    {
        $hospitalId = Auth::user()->hospital_id;

        $stats = [
            'total_patients'    => Patient::where('hospital_id', $hospitalId)->count(),
            'active_patients'   => Patient::where('hospital_id', $hospitalId)->where('is_active', true)->count(),
            'enrolled_patients' => Patient::where('hospital_id', $hospitalId)
                ->whereHas('activeFingerprints')
                ->count(),
            'total_staff'       => User::where('hospital_id', $hospitalId)->where('is_active', true)->count(),
            'verifications_today' => VerificationLog::where('hospital_id', $hospitalId)
                ->whereDate('created_at', today())
                ->count(),
            'successful_today'  => VerificationLog::where('hospital_id', $hospitalId)
                ->whereDate('created_at', today())
                ->where('status', 'matched')
                ->count(),
            'verifications_week' => VerificationLog::where('hospital_id', $hospitalId)
                ->where('created_at', '>=', now()->subDays(7))
                ->count(),
            'success_rate'      => $this->successRate($hospitalId),
        ];

        $recentLogs = VerificationLog::with(['patient:id,full_name', 'operator:id,name'])
            ->where('hospital_id', $hospitalId)
            ->latest()
            ->limit(8)
            ->get();

        $recentPatients = Patient::where('hospital_id', $hospitalId)
            ->latest()
            ->limit(5)
            ->get();

        return view('dashboard.index', compact('stats', 'recentLogs', 'recentPatients'));
    }

    public function patients(Request $request): View
    {
        $hospitalId = Auth::user()->hospital_id;

        $query = Patient::with(['fingerprints' => fn ($q) => $q->where('is_active', true)])
            ->where('hospital_id', $hospitalId);

        if ($search = $request->get('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('full_name', 'like', "%{$search}%")
                  ->orWhere('jmbg', 'like', "%{$search}%")
                  ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        if ($request->get('enrolled') === '1') {
            $query->whereHas('activeFingerprints');
        } elseif ($request->get('enrolled') === '0') {
            $query->whereDoesntHave('activeFingerprints');
        }

        if ($status = $request->get('status')) {
            $query->where('is_active', $status === 'active');
        }

        $patients = $query->latest()->paginate(20)->withQueryString();

        return view('dashboard.patients.index', compact('patients'));
    }

    public function patientShow(Patient $patient): View
    {
        abort_if($patient->hospital_id !== Auth::user()->hospital_id, 404);

        $patient->load([
            'fingerprints' => fn ($q) => $q->orderBy('created_at', 'desc'),
            'verificationLogs' => fn ($q) => $q->with('operator:id,name')->latest()->limit(20),
        ]);

        $verificationStats = [
            'total'   => $patient->verificationLogs()->count(),
            'matched' => $patient->verificationLogs()->where('status', 'matched')->count(),
        ];

        return view('dashboard.patients.show', compact('patient', 'verificationStats'));
    }

    public function logs(Request $request): View
    {
        $hospitalId = Auth::user()->hospital_id;

        $query = VerificationLog::with(['patient:id,full_name', 'operator:id,name'])
            ->where('hospital_id', $hospitalId);

        if ($status = $request->get('status')) {
            $query->where('status', $status);
        }

        if ($from = $request->get('from')) {
            $query->whereDate('created_at', '>=', $from);
        }

        if ($to = $request->get('to')) {
            $query->whereDate('created_at', '<=', $to);
        }

        $logs = $query->latest()->paginate(25)->withQueryString();

        return view('dashboard.logs.index', compact('logs'));
    }

    private function successRate(int $hospitalId): int
    {
        $total = VerificationLog::where('hospital_id', $hospitalId)
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        if ($total === 0) {
            return 0;
        }

        $matched = VerificationLog::where('hospital_id', $hospitalId)
            ->where('created_at', '>=', now()->subDays(30))
            ->where('status', 'matched')
            ->count();

        return (int) round(($matched / $total) * 100);
    }
}
