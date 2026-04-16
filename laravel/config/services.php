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
    | Set PYTHON_SERVICE_URL in .env to point at the running Flask service.
    | Example: PYTHON_SERVICE_URL=http://127.0.0.1:5001
    */

    'fingerprint' => [
        'url' => env('PYTHON_SERVICE_URL', 'http://127.0.0.1:5001'),
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
