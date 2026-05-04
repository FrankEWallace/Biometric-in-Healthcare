<!DOCTYPE html>
<html lang="en" class="h-full bg-slate-50">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>@yield('title', 'Dashboard') — BiH Patient System</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    <style>body { font-family: 'Inter', sans-serif; }</style>
</head>
<body class="h-full" x-data="{ sidebarOpen: false }">

{{-- Mobile overlay --}}
<div x-show="sidebarOpen" x-cloak @click="sidebarOpen = false"
     class="fixed inset-0 z-20 bg-slate-900/50 lg:hidden"></div>

<div class="flex h-full">

    {{-- ── Sidebar ──────────────────────────────────────────────────────── --}}
    <aside :class="sidebarOpen ? 'translate-x-0' : '-translate-x-full'"
           class="fixed inset-y-0 left-0 z-30 flex w-64 flex-col bg-slate-900 transition-transform duration-200 lg:relative lg:translate-x-0">

        {{-- Logo --}}
        <div class="flex h-16 shrink-0 items-center gap-3 px-6 border-b border-slate-700/60">
            <div class="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-600">
                <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"/>
                </svg>
            </div>
            <div>
                <p class="text-sm font-semibold text-white">BiH Patient ID</p>
                @php
                    $roleLabel = match(Auth::user()->role) {
                        'super_admin' => 'Super Admin Panel',
                        'admin'       => 'Admin Panel',
                        'doctor'      => 'Doctor Panel',
                        default       => 'Panel',
                    };
                @endphp
                <p class="text-xs text-slate-400">{{ $roleLabel }}</p>
            </div>
        </div>

        {{-- Nav --}}
        <nav class="flex-1 overflow-y-auto px-3 py-4 space-y-0.5">

            {{-- ── Common nav ──────────────────────────────────────────── --}}
            @php
                $pendingBadge = Auth::user()->isAnyAdmin()
                    ? \App\Models\PatientEditRequest::where('hospital_id', Auth::user()->hospital_id)
                        ->when(! Auth::user()->isSuperAdmin(), fn ($q) => $q)
                        ->pending()->count()
                    : 0;
            @endphp

            {{-- Overview --}}
            <a href="{{ route('dashboard.index') }}"
               class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.index') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/>
                </svg>
                Overview
            </a>

            {{-- Patients --}}
            <a href="{{ route('dashboard.patients') }}"
               class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.patients*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                </svg>
                Patients
            </a>

            {{-- Verification Logs --}}
            <a href="{{ route('dashboard.logs') }}"
               class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.logs*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                </svg>
                Verification Logs
            </a>

            {{-- ── Admin / Super Admin only ─────────────────────────────── --}}
            @if(Auth::user()->isAnyAdmin())
            <div class="pt-4 mt-2 border-t border-slate-700/60">
                <p class="px-3 mb-1.5 text-xs font-semibold uppercase tracking-wider text-slate-500">Management</p>

                {{-- Edit Requests --}}
                <a href="{{ route('dashboard.edit-requests') }}"
                   class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.edit-requests*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                    <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10"/>
                    </svg>
                    Edit Requests
                    @if($pendingBadge > 0)
                    <span class="ml-auto flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-amber-500 px-1.5 text-xs font-bold text-white">
                        {{ $pendingBadge > 99 ? '99+' : $pendingBadge }}
                    </span>
                    @endif
                </a>

                {{-- Staff Management --}}
                <a href="{{ route('dashboard.users') }}"
                   class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.users*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                    <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z"/>
                    </svg>
                    Staff Management
                </a>

                {{-- Audit Logs --}}
                <a href="{{ route('dashboard.audit-logs') }}"
                   class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.audit-logs*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                    <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/>
                    </svg>
                    Audit Logs
                </a>
            </div>
            @endif

            {{-- ── Doctor only ──────────────────────────────────────────── --}}
            @if(Auth::user()->isDoctor())
            <div class="pt-4 mt-2 border-t border-slate-700/60">
                <p class="px-3 mb-1.5 text-xs font-semibold uppercase tracking-wider text-slate-500">Clinical</p>
                <a href="{{ route('dashboard.audit-logs') }}"
                   class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.audit-logs*') ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-800 hover:text-white' }}">
                    <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"/>
                    </svg>
                    My Activity Log
                </a>
            </div>
            @endif

        </nav>

        {{-- ── User footer ───────────────────────────────────────────────── --}}
        <div class="shrink-0 border-t border-slate-700/60 p-4">
            <div class="flex items-center gap-3">
                <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-500 text-sm font-semibold text-white">
                    {{ strtoupper(substr(Auth::user()->name, 0, 1)) }}
                </div>
                <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-white truncate">{{ Auth::user()->name }}</p>
                    @php
                        $roleBadge = match(Auth::user()->role) {
                            'super_admin' => ['label' => 'Super Admin', 'class' => 'bg-rose-500/20 text-rose-300'],
                            'admin'       => ['label' => 'Admin',       'class' => 'bg-amber-500/20 text-amber-300'],
                            'doctor'      => ['label' => 'Doctor',      'class' => 'bg-sky-500/20 text-sky-300'],
                            'nurse'       => ['label' => 'Nurse',       'class' => 'bg-emerald-500/20 text-emerald-300'],
                            default       => ['label' => ucfirst(Auth::user()->role), 'class' => 'bg-slate-500/20 text-slate-300'],
                        };
                    @endphp
                    <span class="inline-flex items-center rounded-full px-1.5 py-0.5 text-xs font-medium {{ $roleBadge['class'] }}">
                        {{ $roleBadge['label'] }}
                    </span>
                </div>
                <form method="POST" action="{{ route('logout') }}">
                    @csrf
                    <button type="submit" class="text-slate-400 hover:text-white transition-colors" title="Sign out">
                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round"
                                  d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75"/>
                        </svg>
                    </button>
                </form>
            </div>
        </div>
    </aside>

    {{-- ── Main content ──────────────────────────────────────────────────── --}}
    <div class="flex flex-1 flex-col min-w-0 overflow-hidden">

        {{-- Top bar --}}
        <header class="flex h-16 shrink-0 items-center gap-4 border-b border-slate-200 bg-white px-4 lg:px-6">
            <button @click="sidebarOpen = !sidebarOpen"
                    class="lg:hidden rounded-md p-1.5 text-slate-500 hover:bg-slate-100">
                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/>
                </svg>
            </button>

            <div class="flex-1">
                <h1 class="text-base font-semibold text-slate-800">@yield('title', 'Overview')</h1>
                @hasSection('subtitle')
                <p class="text-xs text-slate-400 mt-0.5">@yield('subtitle')</p>
                @endif
            </div>

            <div class="flex items-center gap-3">
                {{-- Flash message --}}
                @if(session('success'))
                <span class="hidden sm:inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-medium text-emerald-700 border border-emerald-200">
                    <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                    </svg>
                    {{ session('success') }}
                </span>
                @else
                <span class="hidden sm:inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-medium text-emerald-700 border border-emerald-200">
                    <span class="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
                    System Online
                </span>
                @endif

                {{-- Hospital name --}}
                @if(Auth::user()->hospital)
                <span class="hidden md:block text-xs text-slate-400 border-l border-slate-200 pl-3">
                    {{ Auth::user()->hospital->name }}
                </span>
                @endif
            </div>
        </header>

        {{-- Page content --}}
        <main class="flex-1 overflow-y-auto">
            <div class="px-4 py-6 lg:px-6 lg:py-8">
                @yield('content')
            </div>
        </main>
    </div>

</div>

<script src="//unpkg.com/alpinejs" defer></script>
</body>
</html>
