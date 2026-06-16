<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    */

    'mailgun'     => ['domain' => env('MAILGUN_DOMAIN'), 'secret' => env('MAILGUN_SECRET'), 'endpoint' => env('MAILGUN_ENDPOINT', 'api.mailgun.net')],
    'postmark'    => ['token' => env('POSTMARK_TOKEN')],
    'ses'         => ['key' => env('AWS_ACCESS_KEY_ID'), 'secret' => env('AWS_SECRET_ACCESS_KEY'), 'region' => env('AWS_DEFAULT_REGION', 'us-east-1')],

    /*
    |--------------------------------------------------------------------------
    | Python OpenCV Fingerprint Microservice
    |--------------------------------------------------------------------------
    | Set PYTHON_SERVICE_URL in .env to point at the running FastAPI service.
    | Example: PYTHON_SERVICE_URL=http://127.0.0.1:5001
    |
    | PYTHON_SERVICE_API_KEY must match INTERNAL_API_KEY on the Python side.
    | Required in production — the microservice rejects unauthenticated
    | requests when its key is configured.
    |
    | match_threshold is the SINGLE SOURCE OF TRUTH for the fingerprint
    | accept/reject decision. Keep FINGERPRINT_MATCH_THRESHOLD in sync with
    | the Python service's env var. Set it to the operating point produced by
    | tools/calibrate_far_frr.py (EER, or the threshold at your target FAR).
    */

    'fingerprint' => [
        'url'             => env('PYTHON_SERVICE_URL', 'http://127.0.0.1:5001'),
        'key'             => env('PYTHON_SERVICE_API_KEY', ''),
        'match_threshold' => (float) env('FINGERPRINT_MATCH_THRESHOLD', 32.0),
    ],

    /*
    |--------------------------------------------------------------------------
    | Geofence Policy
    |--------------------------------------------------------------------------
    | When a hospital has configured neither GPS coordinates nor a WiFi
    | SSID, fail_open=true (default) lets requests through. Set
    | GEOFENCE_FAIL_OPEN=false in production to deny instead.
    */

    'geofence' => [
        'fail_open' => env('GEOFENCE_FAIL_OPEN', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | GoT-HoMIS Integration
    |--------------------------------------------------------------------------
    | Set HOMIS_BASE_URL and HOMIS_API_KEY in .env.
    | Example: HOMIS_BASE_URL=https://homis.moh.go.tz/api/v1
    */

    'homis' => [
        'url'     => env('HOMIS_BASE_URL', ''),
        'key'     => env('HOMIS_API_KEY', ''),
        'timeout' => (int) env('HOMIS_TIMEOUT', 10),
        'retries' => (int) env('HOMIS_RETRIES', 3),
    ],

];
