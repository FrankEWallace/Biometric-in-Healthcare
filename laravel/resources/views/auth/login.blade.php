<!DOCTYPE html>
<html lang="en" class="h-full bg-slate-50">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sign In — BiH Patient ID System</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    @vite(['resources/css/app.css'])
    <style>body { font-family: 'Inter', sans-serif; }</style>
</head>
<body class="h-full">

<div class="flex min-h-full">

    {{-- Left panel --}}
    <div class="hidden lg:flex lg:flex-1 flex-col justify-between bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 px-12 py-16">
        <div class="flex items-center gap-3">
            <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-600">
                <svg class="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"/>
                </svg>
            </div>
            <span class="text-lg font-semibold text-white">BiH Patient ID</span>
        </div>

        <div>
            <h2 class="text-4xl font-bold text-white leading-tight">
                Fingerprint-Based<br>Patient Identification
            </h2>
            <p class="mt-4 text-slate-400 text-lg leading-relaxed max-w-md">
                Secure, accurate patient verification for healthcare professionals — powered by biometric matching.
            </p>

            <div class="mt-10 grid grid-cols-2 gap-4">
                @foreach([
                    ['label' => 'Biometric Enrollment', 'desc' => 'Multi-finger capture'],
                    ['label' => 'GPS Geofencing',        'desc' => 'Hospital-only access'],
                    ['label' => 'GoT-HoMIS Ready',       'desc' => 'Integrated EHR'],
                    ['label' => 'PDPA Compliant',        'desc' => 'Full audit trail'],
                ] as $f)
                <div class="rounded-xl border border-slate-700/50 bg-slate-800/40 p-4">
                    <p class="text-sm font-semibold text-white">{{ $f['label'] }}</p>
                    <p class="text-xs text-slate-400 mt-0.5">{{ $f['desc'] }}</p>
                </div>
                @endforeach
            </div>
        </div>

        <p class="text-xs text-slate-600">© {{ date('Y') }} BiH Healthcare System. All rights reserved.</p>
    </div>

    {{-- Right panel — form --}}
    <div class="flex flex-1 flex-col items-center justify-center px-6 py-12 lg:max-w-md">
        <div class="w-full max-w-sm">

            {{-- Mobile logo --}}
            <div class="flex lg:hidden items-center gap-3 mb-8 justify-center">
                <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-600">
                    <svg class="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"/>
                    </svg>
                </div>
                <span class="text-lg font-semibold text-slate-900">BiH Patient ID</span>
            </div>

            <h1 class="text-2xl font-bold text-slate-900">Welcome back</h1>
            <p class="mt-1 text-sm text-slate-500">Sign in to the admin panel</p>

            @if($errors->any())
            <div class="mt-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3">
                <p class="text-sm text-red-700">{{ $errors->first() }}</p>
            </div>
            @endif

            <form method="POST" action="{{ route('login.post') }}" class="mt-8 space-y-5">
                @csrf

                <div>
                    <label for="username" class="block text-sm font-medium text-slate-700 mb-1.5">Username</label>
                    <input
                        type="text"
                        id="username"
                        name="username"
                        value="{{ old('username') }}"
                        required
                        autofocus
                        autocomplete="username"
                        class="w-full rounded-lg border border-slate-300 px-3.5 py-2.5 text-sm text-slate-900 placeholder-slate-400
                               shadow-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20
                               @error('username') border-red-400 @enderror"
                        placeholder="Enter your username"
                    >
                </div>

                <div>
                    <label for="password" class="block text-sm font-medium text-slate-700 mb-1.5">Password</label>
                    <input
                        type="password"
                        id="password"
                        name="password"
                        required
                        autocomplete="current-password"
                        class="w-full rounded-lg border border-slate-300 px-3.5 py-2.5 text-sm text-slate-900
                               shadow-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20"
                        placeholder="••••••••"
                    >
                </div>

                <button type="submit"
                        class="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm
                               hover:bg-blue-700 active:scale-[.98] transition-all focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2">
                    Sign in
                </button>
            </form>

            <p class="mt-8 text-center text-xs text-slate-400">
                Access restricted to authorised hospital staff only.
            </p>
        </div>
    </div>

</div>

</body>
</html>
