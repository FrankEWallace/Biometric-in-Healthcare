<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Fingerprint;
use App\Models\Hospital;
use App\Models\Patient;
use App\Models\PatientEditRequest;
use App\Models\User;
use App\Models\VerificationLog;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

class DashboardController extends Controller
{
    // ── Overview ──────────────────────────────────────────────────────────────

    public function index(): View
    {
        $user = Auth::user();

        if ($user->isSuperAdmin()) {
            return $this->superAdminOverview();
        }

        if ($user->isDoctor()) {
            return $this->doctorOverview();
        }

        return $this->adminOverview();
    }

    private function adminOverview(): View
    {
        $hospitalId = Auth::user()->hospital_id;

        $pendingCount = PatientEditRequest::where('hospital_id', $hospitalId)->pending()->count();
        $lockedCount  = Fingerprint::where('hospital_id', $hospitalId)->whereNotNull('locked_at')->count();

        $stats = [
            'total_patients'      => Patient::where('hospital_id', $hospitalId)->count(),
            'active_patients'     => Patient::where('hospital_id', $hospitalId)->where('is_active', true)->count(),
            'enrolled_patients'   => Patient::where('hospital_id', $hospitalId)->whereHas('activeFingerprints')->count(),
            'total_staff'         => User::where('hospital_id', $hospitalId)->where('is_active', true)->count(),
            'verifications_today' => VerificationLog::where('hospital_id', $hospitalId)->whereDate('created_at', today())->count(),
            'successful_today'    => VerificationLog::where('hospital_id', $hospitalId)->whereDate('created_at', today())->where('status', 'matched')->count(),
            'verifications_week'  => VerificationLog::where('hospital_id', $hospitalId)->where('created_at', '>=', now()->subDays(7))->count(),
            'success_rate'        => $this->successRate($hospitalId),
            'pending_requests'    => $pendingCount,
            'locked_fingerprints' => $lockedCount,
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

        $pendingRequests = PatientEditRequest::with(['patient:id,full_name', 'requestedBy:id,name'])
            ->where('hospital_id', $hospitalId)
            ->pending()
            ->latest()
            ->limit(4)
            ->get();

        $lockedFingerprints = Fingerprint::with('patient:id,full_name')
            ->where('hospital_id', $hospitalId)
            ->whereNotNull('locked_at')
            ->latest('locked_at')
            ->limit(3)
            ->get();

        return view('dashboard.index', compact(
            'stats', 'recentLogs', 'recentPatients', 'pendingRequests', 'lockedFingerprints'
        ));
    }

    private function superAdminOverview(): View
    {
        $hospitals = Hospital::where('is_active', true)->withCount(['patients', 'users'])->get();

        $hospitalStats = $hospitals->map(function (Hospital $hospital) {
            return [
                'id'            => $hospital->id,
                'name'          => $hospital->name,
                'city'          => $hospital->city ?? '—',
                'patients'      => $hospital->patients_count,
                'staff'         => $hospital->users_count,
                'enrolled'      => Patient::where('hospital_id', $hospital->id)->whereHas('activeFingerprints')->count(),
                'ver_today'     => VerificationLog::where('hospital_id', $hospital->id)->whereDate('created_at', today())->count(),
                'success_today' => VerificationLog::where('hospital_id', $hospital->id)->whereDate('created_at', today())->where('status', 'matched')->count(),
                'pending_requests' => PatientEditRequest::where('hospital_id', $hospital->id)->pending()->count(),
                'locked_fps'    => Fingerprint::where('hospital_id', $hospital->id)->whereNotNull('locked_at')->count(),
            ];
        });

        $verToday     = VerificationLog::whereDate('created_at', today())->count();
        $matchToday   = VerificationLog::whereDate('created_at', today())->where('status', 'matched')->count();

        $stats = [
            'total_hospitals'     => $hospitals->count(),
            'total_patients'      => Patient::count(),
            'total_enrolled'      => Patient::whereHas('activeFingerprints')->count(),
            'verifications_today' => $verToday,
            'successful_today'    => $matchToday,
            'total_staff'         => User::where('is_active', true)->count(),
            'pending_requests'    => PatientEditRequest::pending()->count(),
            'success_rate'        => $verToday > 0 ? (int) round(($matchToday / $verToday) * 100) : 0,
        ];

        $recentAudit = AuditLog::with('staff:id,name')
            ->latest()
            ->limit(10)
            ->get();

        return view('dashboard.index', compact('stats', 'hospitalStats', 'recentAudit'));
    }

    private function doctorOverview(): View
    {
        $hospitalId = Auth::user()->hospital_id;

        $verToday   = VerificationLog::where('hospital_id', $hospitalId)->whereDate('created_at', today())->count();
        $matchToday = VerificationLog::where('hospital_id', $hospitalId)->whereDate('created_at', today())->where('status', 'matched')->count();

        $stats = [
            'active_patients'     => Patient::where('hospital_id', $hospitalId)->where('is_active', true)->count(),
            'verifications_today' => $verToday,
            'successful_today'    => $matchToday,
            'success_rate'        => $verToday > 0 ? (int) round(($matchToday / $verToday) * 100) : 0,
        ];

        $recentLogs = VerificationLog::with(['patient:id,full_name', 'operator:id,name'])
            ->where('hospital_id', $hospitalId)
            ->latest()
            ->limit(10)
            ->get();

        return view('dashboard.index', compact('stats', 'recentLogs'));
    }

    // ── Patients ──────────────────────────────────────────────────────────────

    public function patients(Request $request): View
    {
        $user  = Auth::user();
        $query = Patient::with(['fingerprints' => fn ($q) => $q->where('is_active', true)]);

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        if ($search = $request->get('search')) {
            $query->where(fn ($q) => $q
                ->where('full_name', 'like', "%{$search}%")
                ->orWhere('jmbg', 'like', "%{$search}%")
                ->orWhere('phone', 'like', "%{$search}%")
            );
        }

        if ($request->get('enrolled') === '1') { $query->whereHas('activeFingerprints'); }
        if ($request->get('enrolled') === '0') { $query->whereDoesntHave('activeFingerprints'); }
        if ($status = $request->get('status')) { $query->where('is_active', $status === 'active'); }

        $patients  = $query->latest()->paginate(20)->withQueryString();
        $hospitals = $user->isSuperAdmin()
            ? Hospital::where('is_active', true)->get(['id', 'name'])
            : collect();

        return view('dashboard.patients.index', compact('patients', 'hospitals'));
    }

    public function patientShow(Patient $patient): View
    {
        $user = Auth::user();
        if (! $user->isSuperAdmin()) {
            abort_if($patient->hospital_id !== $user->hospital_id, 404);
        }

        $patient->load([
            'fingerprints'     => fn ($q) => $q->orderBy('created_at', 'desc'),
            'verificationLogs' => fn ($q) => $q->with('operator:id,name')->latest()->limit(20),
        ]);

        $verificationStats = [
            'total'   => $patient->verificationLogs()->count(),
            'matched' => $patient->verificationLogs()->where('status', 'matched')->count(),
        ];

        return view('dashboard.patients.show', compact('patient', 'verificationStats'));
    }

    // ── Verification Logs ─────────────────────────────────────────────────────

    public function logs(Request $request): View
    {
        $user  = Auth::user();
        $query = VerificationLog::with(['patient:id,full_name', 'operator:id,name']);

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        if ($status = $request->get('status')) { $query->where('status', $status); }
        if ($from   = $request->get('from'))   { $query->whereDate('created_at', '>=', $from); }
        if ($to     = $request->get('to'))     { $query->whereDate('created_at', '<=', $to); }

        $logs = $query->latest()->paginate(25)->withQueryString();

        if ($user->isDoctor()) {
            $logs->getCollection()->transform(fn ($l) => tap($l, fn ($l) => $l->makeHidden('score')));
        }

        return view('dashboard.logs.index', compact('logs'));
    }

    // ── Edit Requests ─────────────────────────────────────────────────────────

    public function editRequests(Request $request): View
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);

        $user  = Auth::user();
        $query = PatientEditRequest::with(['patient:id,full_name', 'requestedBy:id,name', 'reviewedBy:id,name']);

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        $status   = $request->get('status', 'pending');
        $query->where('status', $status);

        $requests  = $query->latest()->paginate(20)->withQueryString();
        $hospitals = $user->isSuperAdmin()
            ? Hospital::where('is_active', true)->get(['id', 'name'])
            : collect();

        return view('dashboard.edit-requests.index', compact('requests', 'hospitals', 'status'));
    }

    public function approveEditRequest(Request $request, int $id): RedirectResponse
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);

        $user        = Auth::user();
        $editRequest = PatientEditRequest::findOrFail($id);

        abort_if(! $user->isSuperAdmin() && $editRequest->hospital_id !== $user->hospital_id, 403);
        abort_if($editRequest->status !== PatientEditRequest::STATUS_PENDING, 409);

        $patient = $editRequest->patient;
        $patient->{$editRequest->field_name} = $editRequest->new_value;
        $patient->save();

        $editRequest->status      = PatientEditRequest::STATUS_APPROVED;
        $editRequest->reviewed_by = $user->id;
        $editRequest->reviewed_at = now();
        $editRequest->save();

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_APPROVED, $patient->id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $editRequest->field_name,
            'new_value'       => $editRequest->new_value,
        ]);

        return redirect()->route('dashboard.edit-requests')->with('success', 'Edit request approved and patient record updated.');
    }

    public function rejectEditRequest(Request $request, int $id): RedirectResponse
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);

        $user        = Auth::user();
        $editRequest = PatientEditRequest::findOrFail($id);

        abort_if(! $user->isSuperAdmin() && $editRequest->hospital_id !== $user->hospital_id, 403);
        abort_if($editRequest->status !== PatientEditRequest::STATUS_PENDING, 409);

        $editRequest->status      = PatientEditRequest::STATUS_REJECTED;
        $editRequest->reviewed_by = $user->id;
        $editRequest->reviewed_at = now();
        $editRequest->save();

        AuditLog::record($request, AuditLog::ACTION_EDIT_REQUEST_REJECTED, $editRequest->patient_id, null, null, [
            'edit_request_id' => $editRequest->id,
            'field'           => $editRequest->field_name,
        ]);

        return redirect()->route('dashboard.edit-requests')->with('success', 'Edit request rejected.');
    }

    // ── Staff Management ──────────────────────────────────────────────────────

    public function users(Request $request): View
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);

        $user  = Auth::user();
        $query = User::with('hospital:id,name');

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        if ($role   = $request->get('role'))   { $query->where('role', $role); }
        if ($search = $request->get('search')) {
            $query->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('username', 'like', "%{$search}%")
                ->orWhere('email', 'like', "%{$search}%")
            );
        }

        $users     = $query->orderBy('name')->paginate(20)->withQueryString();
        $hospitals = $user->isSuperAdmin()
            ? Hospital::where('is_active', true)->get(['id', 'name'])
            : collect();

        return view('dashboard.users.index', compact('users', 'hospitals'));
    }

    public function deactivateUser(Request $request, User $targetUser): RedirectResponse
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);
        abort_if($targetUser->id === Auth::id(), 403, 'You cannot deactivate your own account.');
        abort_if(! Auth::user()->isSuperAdmin() && $targetUser->hospital_id !== Auth::user()->hospital_id, 403);

        $targetUser->is_active = false;
        $targetUser->save();

        AuditLog::record($request, AuditLog::ACTION_USER_DEACTIVATED, null, null, null, [
            'target_user_id'   => $targetUser->id,
            'target_user_name' => $targetUser->name,
            'target_role'      => $targetUser->role,
        ]);

        return back()->with('success', "{$targetUser->name} has been deactivated.");
    }

    public function activateUser(Request $request, User $targetUser): RedirectResponse
    {
        abort_unless(Auth::user()->isAnyAdmin(), 403);
        abort_if(! Auth::user()->isSuperAdmin() && $targetUser->hospital_id !== Auth::user()->hospital_id, 403);

        $targetUser->is_active = true;
        $targetUser->save();

        return back()->with('success', "{$targetUser->name} has been reactivated.");
    }

    // ── Audit Logs ────────────────────────────────────────────────────────────

    public function auditLogs(Request $request): View
    {
        $user = Auth::user();
        abort_unless($user->isAnyAdmin() || $user->isDoctor(), 403);

        $query = AuditLog::with('staff:id,name');

        if ($user->isSuperAdmin()) {
            if ($h = $request->integer('hospital_id')) {
                $query->where('hospital_id', $h);
            }
        } elseif ($user->isDoctor()) {
            $query->where('staff_id', $user->id);
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        if ($action = $request->get('action')) { $query->where('action', $action); }
        if ($from   = $request->get('from'))   { $query->whereDate('created_at', '>=', $from); }
        if ($to     = $request->get('to'))     { $query->whereDate('created_at', '<=', $to); }

        $logs = $query->latest()->paginate(30)->withQueryString();

        return view('dashboard.audit-logs.index', compact('logs'));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private function successRate(int $hospitalId): int
    {
        $total = VerificationLog::where('hospital_id', $hospitalId)
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        if ($total === 0) { return 0; }

        $matched = VerificationLog::where('hospital_id', $hospitalId)
            ->where('created_at', '>=', now()->subDays(30))
            ->where('status', 'matched')
            ->count();

        return (int) round(($matched / $total) * 100);
    }
}
