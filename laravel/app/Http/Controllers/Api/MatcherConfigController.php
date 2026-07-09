<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FaceService;
use Illuminate\Http\JsonResponse;

class MatcherConfigController extends Controller
{
    /**
     * GET /api/matcher-config
     * super_admin only.
     *
     * Read-only snapshot of the matcher operating points the backend is
     * actually using. Fingerprint thresholds come from env-backed config
     * and face thresholds are code constants — none of these are editable
     * at runtime, so there is deliberately no write endpoint.
     */
    public function show(): JsonResponse
    {
        return response()->json([
            'fingerprint' => [
                'match_threshold'             => (float) config('services.fingerprint.match_threshold'),
                'contactless_match_threshold' => config('services.fingerprint.contactless_match_threshold'),
                'service_url'                 => (string) config('services.fingerprint.url'),
            ],
            'face' => [
                'match_threshold'    => FaceService::MATCH_THRESHOLD,
                'identify_threshold' => FaceService::IDENTIFY_THRESHOLD,
            ],
            'geofence' => [
                'fail_open' => (bool) config('services.geofence.fail_open'),
            ],
            'source' => 'env', // values change via .env + deploy, not via this API
        ]);
    }
}
