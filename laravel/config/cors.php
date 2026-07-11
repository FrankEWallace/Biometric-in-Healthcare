<?php

return [
    'paths' => ['api/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_values(array_filter([
        'http://localhost:*',
        'http://127.0.0.1:*',
        // Production Next.js admin origin, e.g. https://admin.your-domain.
        // Empty in local dev (the LAN pattern below covers those).
        env('WEB_ADMIN_ORIGIN'),
    ])),

    'allowed_origins_patterns' => [
        '/^http:\/\/localhost(:\d+)?$/',
        '/^http:\/\/127\.0\.0\.1(:\d+)?$/',
        '/^http:\/\/192\.168\.\d{1,3}\.\d{1,3}(:\d+)?$/',
    ],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,
];
