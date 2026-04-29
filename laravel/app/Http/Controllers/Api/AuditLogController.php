<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuditLogController extends Controller
{
    /**
     * GET /api/audit-logs
     *
     * Visibility:
     *   super_admin — all hospitals, all actions
     *   admin       — own hospital, all actions
     *   doctor      — own actions only (what they personally accessed)
     *   nurse       — forbidden (enforced by route middleware)
     */
    public function index(Request $request): JsonResponse
    {
        $user  = $request->user();
        $query = AuditLog::with(['staff:id,name,role', 'patient:id,full_name'])
            ->orderByDesc('created_at');

        if ($user->isSuperAdmin()) {
            // Full visibility — optional hospital filter
            if ($hospitalId = $request->integer('hospital_id')) {
                $query->where('hospital_id', $hospitalId);
            }
        } elseif ($user->isAdmin()) {
            $query->where('hospital_id', $user->hospital_id);
        } elseif ($user->isDoctor()) {
            // Doctors see only their own audit entries
            $query->where('staff_id', $user->id);
        }

        // Common filters
        if ($v = $request->query('action'))     { $query->where('action', $v); }
        if ($v = $request->query('patient_id')) { $query->where('patient_id', $v); }
        if ($v = $request->query('staff_id') and $user->isAnyAdmin()) {
            $query->where('staff_id', $v);
        }
        if ($from = $request->query('from')) { $query->whereDate('created_at', '>=', $from); }
        if ($to   = $request->query('to'))   { $query->whereDate('created_at', '<=', $to); }

        return response()->json($query->paginate($request->integer('per_page', 50)));
    }
}
