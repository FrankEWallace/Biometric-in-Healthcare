<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DeviceController extends Controller
{
    /**
     * GET /api/devices
     *
     * Read-only device inventory derived from audit logs — there is no
     * device-pairing table; a "device" is a distinct (ip_address,
     * user_agent) pair that has hit the API.
     *
     * Visibility:
     *   super_admin — all hospitals, optional ?hospital_id filter
     *   admin       — own hospital only
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $query = AuditLog::query()
            ->whereNotNull('ip_address')
            ->selectRaw(
                'ip_address, user_agent,'
                . ' COUNT(*)        as request_count,'
                . ' MAX(created_at) as last_seen_at,'
                . ' MAX(id)         as last_log_id'
            )
            ->groupBy('ip_address', 'user_agent')
            ->orderByDesc('last_seen_at');

        if ($user->isSuperAdmin()) {
            if ($hospitalId = $request->integer('hospital_id')) {
                $query->where('hospital_id', $hospitalId);
            }
        } else {
            $query->where('hospital_id', $user->hospital_id);
        }

        $devices = $query->limit(200)->get();

        // Resolve who used each device last (and from which hospital)
        // from the newest audit row in each group.
        $lastLogs = AuditLog::with(['staff:id,name,role', 'hospital:id,name'])
            ->findMany($devices->pluck('last_log_id'))
            ->keyBy('id');

        return response()->json([
            'devices' => $devices->map(function ($device) use ($lastLogs) {
                $last = $lastLogs->get($device->last_log_id);

                return [
                    'ip_address'    => $device->ip_address,
                    'user_agent'    => $device->user_agent,
                    'request_count' => (int) $device->request_count,
                    'last_seen_at'  => $device->last_seen_at,
                    'last_staff'    => $last?->staff,
                    'hospital'      => $last?->hospital,
                    'last_action'   => $last?->action,
                ];
            })->values(),
        ]);
    }
}
