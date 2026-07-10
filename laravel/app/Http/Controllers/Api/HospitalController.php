<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Hospital;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class HospitalController extends Controller
{
    /**
     * GET /api/hospitals
     * All authenticated users — returns active hospitals for geofencing checks.
     * super_admin sees all; others see only active ones.
     */
    public function index(Request $request): JsonResponse
    {
        $query = Hospital::orderBy('name');

        if (! $request->user()->isSuperAdmin()) {
            $query->where('is_active', true);
        }

        return response()->json(['hospitals' => $query->get()]);
    }

    /**
     * POST /api/hospitals
     * super_admin only.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name'               => 'required|string|max:200',
            'code'               => 'required|string|max:20|unique:hospitals,code',
            'city'               => 'required|string|max:100',
            'wifi_ssid'          => 'nullable|string|max:100',
            'gps_latitude'       => 'nullable|numeric|between:-90,90',
            'gps_longitude'      => 'nullable|numeric|between:-180,180',
            'gps_radius_meters'  => 'nullable|integer|min:50|max:5000',
            'is_active'          => 'boolean',
        ]);

        $hospital = Hospital::create($data);

        AuditLog::record($request, 'hospital_created', null, null, null, [
            'hospital_id'   => $hospital->id,
            'hospital_name' => $hospital->name,
        ]);

        return response()->json(['hospital' => $hospital], 201);
    }

    /**
     * GET /api/hospitals/{hospital}
     * All authenticated users.
     */
    public function show(Hospital $hospital): JsonResponse
    {
        return response()->json(['hospital' => $hospital]);
    }

    /**
     * PUT /api/hospitals/{hospital}
     * super_admin: any hospital.
     * admin: own hospital only (GPS/WiFi fields only).
     */
    public function update(Request $request, Hospital $hospital): JsonResponse
    {
        $caller = $request->user();

        if (! $caller->isSuperAdmin() && $caller->hospital_id !== $hospital->id) {
            return response()->json(['message' => 'Forbidden.'], 403);
        }

        $rules = [
            'wifi_ssid'         => 'nullable|string|max:100',
            'gps_latitude'      => 'nullable|numeric|between:-90,90',
            'gps_longitude'     => 'nullable|numeric|between:-180,180',
            'gps_radius_meters' => 'nullable|integer|min:50|max:5000',
        ];

        if ($caller->isSuperAdmin()) {
            $rules['name']      = 'sometimes|string|max:200';
            $rules['city']      = 'sometimes|string|max:100';
            $rules['is_active'] = 'sometimes|boolean';
            $rules['code']      = 'sometimes|string|max:20|unique:hospitals,code,' . $hospital->id;
        }

        $hospital->fill($request->validate($rules));

        // Perimeter/config changes are security-relevant (they move the
        // geofence or WiFi gate) — record which fields changed, keys only.
        $changed = array_keys($hospital->getDirty());
        $hospital->save();

        if ($changed !== []) {
            AuditLog::record($request, AuditLog::ACTION_HOSPITAL_UPDATED, null, null, null, [
                'hospital_id'    => $hospital->id,
                'fields_changed' => $changed,
            ]);
        }

        return response()->json(['hospital' => $hospital->fresh()]);
    }

    /**
     * DELETE /api/hospitals/{hospital}
     * super_admin only — soft-deactivates.
     */
    public function destroy(Request $request, Hospital $hospital): JsonResponse
    {
        $hospital->update(['is_active' => false]);

        AuditLog::record($request, 'hospital_deactivated', null, null, null, [
            'hospital_id'   => $hospital->id,
            'hospital_name' => $hospital->name,
        ]);

        return response()->json(['message' => 'Hospital deactivated.']);
    }
}
