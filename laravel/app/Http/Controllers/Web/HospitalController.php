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
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class HospitalController extends Controller
{
    public function __construct()
    {
        // Every action in this controller requires super_admin
        $this->middleware(function ($request, $next) {
            abort_unless(Auth::user()?->isSuperAdmin(), 403);
            return $next($request);
        });
    }

    // ── List ──────────────────────────────────────────────────────────────────

    public function index(Request $request): View
    {
        $query = Hospital::withCount(['patients', 'users']);

        if ($search = $request->get('search')) {
            $query->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('city', 'like', "%{$search}%")
            );
        }

        if ($status = $request->get('status')) {
            $query->where('is_active', $status === 'active');
        }

        $hospitals = $query->orderBy('name')->paginate(20)->withQueryString();

        return view('dashboard.hospitals.index', compact('hospitals'));
    }

    // ── Create ────────────────────────────────────────────────────────────────

    public function create(): View
    {
        return view('dashboard.hospitals.create');
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'name'              => 'required|string|max:200|unique:hospitals,name',
            'city'              => 'required|string|max:100',
            'wifi_ssid'         => 'nullable|string|max:100',
            'gps_latitude'      => 'nullable|numeric|between:-90,90',
            'gps_longitude'     => 'nullable|numeric|between:-180,180',
            'gps_radius_meters' => 'nullable|integer|min:50|max:5000',
        ]);

        $hospital = Hospital::create([
            'name'              => $data['name'],
            'city'              => $data['city'],
            'wifi_ssid'         => $data['wifi_ssid'] ?? null,
            'gps_latitude'      => $data['gps_latitude'] ?? null,
            'gps_longitude'     => $data['gps_longitude'] ?? null,
            'gps_radius_meters' => $data['gps_radius_meters'] ?? 200,
            'is_active'         => true,
        ]);

        AuditLog::record($request, AuditLog::ACTION_HOSPITAL_CREATED, null, null, null, [
            'hospital_id'   => $hospital->id,
            'hospital_name' => $hospital->name,
        ]);

        return redirect()->route('dashboard.hospitals.show', $hospital)
            ->with('success', "Hospital \"{$hospital->name}\" created.");
    }

    // ── Show (tabbed detail) ──────────────────────────────────────────────────

    public function show(Request $request, Hospital $hospital): View
    {
        $tab = $request->get('tab', 'overview');

        // Overview stats
        $verToday   = VerificationLog::where('hospital_id', $hospital->id)->whereDate('created_at', today())->count();
        $matchToday = VerificationLog::where('hospital_id', $hospital->id)->whereDate('created_at', today())->where('status', 'matched')->count();

        $stats = [
            'total_patients'  => Patient::where('hospital_id', $hospital->id)->count(),
            'enrolled'        => Patient::where('hospital_id', $hospital->id)->whereHas('activeFingerprints')->count(),
            'ver_today'       => $verToday,
            'success_today'   => $matchToday,
            'match_rate'      => $verToday > 0 ? (int) round(($matchToday / $verToday) * 100) : 0,
            'total_staff'     => User::where('hospital_id', $hospital->id)->where('is_active', true)->count(),
            'pending_edits'   => PatientEditRequest::where('hospital_id', $hospital->id)->pending()->count(),
            'locked_fps'      => Fingerprint::where('hospital_id', $hospital->id)->whereNotNull('locked_at')->count(),
        ];

        // Staff tab
        $staffQuery = User::where('hospital_id', $hospital->id);
        if ($role   = $request->get('role'))   { $staffQuery->where('role', $role); }
        if ($search = $request->get('search')) {
            $staffQuery->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('username', 'like', "%{$search}%")
                ->orWhere('email', 'like', "%{$search}%")
            );
        }
        $staff = $staffQuery->orderBy('name')->paginate(15, ['*'], 'staff_page')->withQueryString();

        return view('dashboard.hospitals.show', compact('hospital', 'tab', 'stats', 'staff'));
    }

    // ── Update ────────────────────────────────────────────────────────────────

    public function update(Request $request, Hospital $hospital): RedirectResponse
    {
        $data = $request->validate([
            'name'                     => ['required', 'string', 'max:200', Rule::unique('hospitals', 'name')->ignore($hospital->id)],
            'city'                     => 'required|string|max:100',
            'wifi_ssid'                => 'nullable|string|max:100',
            'gps_latitude'             => 'nullable|numeric|between:-90,90',
            'gps_longitude'            => 'nullable|numeric|between:-180,180',
            'gps_radius_meters'        => 'nullable|integer|min:50|max:5000',
            'face_recognition_enabled' => 'nullable|boolean',
        ]);

        $hospital->update([
            'name'                     => $data['name'],
            'city'                     => $data['city'],
            'wifi_ssid'                => $data['wifi_ssid'] ?? null,
            'gps_latitude'             => $data['gps_latitude'] ?? null,
            'gps_longitude'            => $data['gps_longitude'] ?? null,
            'gps_radius_meters'        => $data['gps_radius_meters'] ?? $hospital->gps_radius_meters,
            'face_recognition_enabled' => $request->boolean('face_recognition_enabled'),
        ]);

        return redirect()->route('dashboard.hospitals.show', [$hospital, 'tab' => 'settings'])
            ->with('success', 'Hospital settings updated.');
    }

    // ── Deactivate / Reactivate ───────────────────────────────────────────────

    public function deactivate(Request $request, Hospital $hospital): RedirectResponse
    {
        abort_if(! $hospital->is_active, 409);

        $hospital->update(['is_active' => false]);

        AuditLog::record($request, AuditLog::ACTION_HOSPITAL_DEACTIVATED, null, null, null, [
            'hospital_id'   => $hospital->id,
            'hospital_name' => $hospital->name,
        ]);

        return redirect()->route('dashboard.hospitals.index')
            ->with('success', "\"{$hospital->name}\" has been deactivated.");
    }

    public function reactivate(Request $request, Hospital $hospital): RedirectResponse
    {
        abort_if($hospital->is_active, 409);

        $hospital->update(['is_active' => true]);

        return redirect()->route('dashboard.hospitals.show', $hospital)
            ->with('success', "\"{$hospital->name}\" has been reactivated.");
    }

    // ── Staff: Create user for this hospital ──────────────────────────────────

    public function storeStaff(Request $request, Hospital $hospital): RedirectResponse
    {
        $data = $request->validate([
            'name'     => 'required|string|max:200',
            'username' => 'required|string|max:80|unique:users,username',
            'email'    => 'required|email|unique:users,email',
            'password' => 'required|string|min:8|confirmed',
            'role'     => ['required', Rule::in(['admin', 'doctor', 'nurse'])],
        ]);

        $user = User::create([
            'name'        => $data['name'],
            'username'    => $data['username'],
            'email'       => $data['email'],
            'password'    => Hash::make($data['password']),
            'role'        => $data['role'],
            'hospital_id' => $hospital->id,
            'is_active'   => true,
        ]);

        AuditLog::record($request, AuditLog::ACTION_USER_CREATED, null, null, null, [
            'created_user_id'   => $user->id,
            'created_user_role' => $user->role,
            'hospital_id'       => $hospital->id,
        ]);

        return redirect()->route('dashboard.hospitals.show', [$hospital, 'tab' => 'staff'])
            ->with('success', "{$user->name} added as {$user->role}.");
    }

    // ── Staff: Edit role ──────────────────────────────────────────────────────

    public function updateStaffRole(Request $request, Hospital $hospital, User $user): RedirectResponse
    {
        abort_if($user->hospital_id !== $hospital->id, 403);
        abort_if($user->isSuperAdmin(), 403);

        $data = $request->validate([
            'role' => ['required', Rule::in(['admin', 'doctor', 'nurse'])],
        ]);

        $user->update(['role' => $data['role']]);

        return redirect()->route('dashboard.hospitals.show', [$hospital, 'tab' => 'staff'])
            ->with('success', "{$user->name}'s role updated to {$data['role']}.");
    }

    // ── Staff: Activate / Deactivate ──────────────────────────────────────────

    public function deactivateStaff(Request $request, Hospital $hospital, User $user): RedirectResponse
    {
        abort_if($user->hospital_id !== $hospital->id, 403);
        abort_if($user->id === Auth::id(), 403);

        $user->update(['is_active' => false]);

        AuditLog::record($request, AuditLog::ACTION_USER_DEACTIVATED, null, null, null, [
            'target_user_id'   => $user->id,
            'target_user_name' => $user->name,
            'target_role'      => $user->role,
        ]);

        return redirect()->route('dashboard.hospitals.show', [$hospital, 'tab' => 'staff'])
            ->with('success', "{$user->name} deactivated.");
    }

    public function activateStaff(Request $request, Hospital $hospital, User $user): RedirectResponse
    {
        abort_if($user->hospital_id !== $hospital->id, 403);

        $user->update(['is_active' => true]);

        return redirect()->route('dashboard.hospitals.show', [$hospital, 'tab' => 'staff'])
            ->with('success', "{$user->name} reactivated.");
    }
}
