<!DOCTYPE html>
<html lang="en" class="h-full bg-slate-100">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>@yield('title', 'Dashboard') — BiH Patient System</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    <style>body { font-family: 'Inter', sans-serif; }</style>
</head>
<body class="h-full" x-data="{ sidebarOpen: window.innerWidth >= 1024 }" @resize.window="if (window.innerWidth >= 1024) sidebarOpen = true">

{{-- Mobile overlay --}}
<div x-show="sidebarOpen" x-cloak @click="sidebarOpen = false"
     class="fixed inset-0 z-20 bg-slate-900/50 lg:hidden"></div>

<div class="flex min-h-screen">

    {{-- ── Sidebar ──────────────────────────────────────────────────────── --}}
    <aside :class="sidebarOpen ? 'translate-x-0' : '-translate-x-full'"
           class="app-sidebar fixed inset-y-0 left-0 z-30 w-64 flex flex-col bg-white border-r border-slate-200
                  shadow-xl transition-transform duration-200">

        {{-- Logo --}}
        <div class="flex h-16 shrink-0 items-center gap-3 px-5 border-b border-slate-200">
            <div class="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-600 shrink-0">
                <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"/>
                </svg>
            </div>
            <div class="min-w-0">
                <p class="text-sm font-semibold text-slate-900 truncate">BiH Patient ID</p>
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
        <nav class="flex-1 overflow-y-auto px-3 py-3 space-y-0.5">

            @php
                $pendingBadge = Auth::user()->isAnyAdmin()
                    ? \App\Models\PatientEditRequest::where('hospital_id', Auth::user()->hospital_id)
                        ->when(! Auth::user()->isSuperAdmin(), fn ($q) => $q)
                        ->pending()->count()
                    : 0;

                $activeClass   = 'bg-blue-50 text-blue-700 border-l-2 border-blue-600 pl-[10px]';
                $inactiveClass = 'text-slate-600 hover:bg-slate-100 hover:text-slate-900 border-l-2 border-transparent pl-[10px]';
            @endphp

            {{-- Overview --}}
            <a href="{{ route('dashboard.index') }}"
               class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.index') ? $activeClass : $inactiveClass }}">
                <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/>
                </svg>
                Overview
            </a>

            {{-- Patients --}}
            <a href="{{ route('dashboard.patients') }}"
               class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.patients*') ? $activeClass : $inactiveClass }}">
                <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                </svg>
                Patients
            </a>

            {{-- Verification Logs --}}
            <a href="{{ route('dashboard.logs') }}"
               class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                      {{ request()->routeIs('dashboard.logs*') ? $activeClass : $inactiveClass }}">
                <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                </svg>
                Verification Logs
            </a>

            {{-- ── Admin / Super Admin only ─────────────────────────────── --}}
            @if(Auth::user()->isAnyAdmin())
            <div class="pt-4 mt-2 border-t border-slate-100">
                <p class="px-3 mb-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">Management</p>

                {{-- Hospitals (super_admin only) --}}
                @if(Auth::user()->isSuperAdmin())
                <a href="{{ route('dashboard.hospitals.index') }}"
                   class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.hospitals*') ? $activeClass : $inactiveClass }}">
                    <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21"/>
                    </svg>
                    Hospitals
                </a>
                @endif

                {{-- Edit Requests --}}
                <a href="{{ route('dashboard.edit-requests') }}"
                   class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.edit-requests*') ? $activeClass : $inactiveClass }}">
                    <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
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
                   class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.users*') ? $activeClass : $inactiveClass }}">
                    <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z"/>
                    </svg>
                    Staff Management
                </a>

                {{-- Audit Logs --}}
                <a href="{{ route('dashboard.audit-logs') }}"
                   class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.audit-logs*') ? $activeClass : $inactiveClass }}">
                    <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/>
                    </svg>
                    Audit Logs
                </a>
            </div>
            @endif

            {{-- ── Doctor only ──────────────────────────────────────────── --}}
            @if(Auth::user()->isDoctor())
            <div class="pt-4 mt-2 border-t border-slate-100">
                <p class="px-3 mb-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">Clinical</p>
                <a href="{{ route('dashboard.audit-logs') }}"
                   class="flex items-center gap-3 rounded-lg pr-3 py-2.5 text-sm font-medium transition-colors
                          {{ request()->routeIs('dashboard.audit-logs*') ? $activeClass : $inactiveClass }}">
                    <svg class="h-4 w-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round"
                              d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"/>
                    </svg>
                    My Activity Log
                </a>
            </div>
            @endif

        </nav>

        {{-- ── User footer ───────────────────────────────────────────────── --}}
        <div class="shrink-0 border-t border-slate-200 p-4">
            <div class="flex items-center gap-3">
                <a href="{{ route('dashboard.profile') }}" class="shrink-0">
                    <img src="{{ Auth::user()->avatarUrl() }}"
                         alt="{{ Auth::user()->name }}"
                         class="h-8 w-8 rounded-full object-cover border border-slate-200 hover:opacity-80 transition-opacity">
                </a>
                <div class="flex-1 min-w-0">
                    <a href="{{ route('dashboard.profile') }}"
                       class="text-sm font-medium text-slate-900 truncate hover:text-blue-600 transition-colors block">
                        {{ Auth::user()->name }}
                    </a>
                    @php
                        $roleBadge = match(Auth::user()->role) {
                            'super_admin' => ['label' => 'Super Admin', 'class' => 'bg-rose-100 text-rose-700'],
                            'admin'       => ['label' => 'Admin',       'class' => 'bg-amber-100 text-amber-700'],
                            'doctor'      => ['label' => 'Doctor',      'class' => 'bg-sky-100 text-sky-700'],
                            'nurse'       => ['label' => 'Nurse',       'class' => 'bg-emerald-100 text-emerald-700'],
                            default       => ['label' => ucfirst(Auth::user()->role), 'class' => 'bg-slate-100 text-slate-600'],
                        };
                    @endphp
                    <span class="inline-flex items-center rounded-full px-1.5 py-0.5 text-xs font-medium {{ $roleBadge['class'] }}">
                        {{ $roleBadge['label'] }}
                    </span>
                </div>
                <form method="POST" action="{{ route('logout') }}">
                    @csrf
                    <button type="submit" class="text-slate-400 hover:text-slate-700 transition-colors" title="Sign out">
                        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round"
                                  d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75"/>
                        </svg>
                    </button>
                </form>
            </div>
        </div>
    </aside>

    {{-- ── Main content ──────────────────────────────────────────────────── --}}
    <div class="flex flex-1 flex-col min-w-0 overflow-x-hidden lg:ml-64">

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

{{-- Alpine.js bundled via Vite (see resources/js/app.js) --}}
</body>
</html>
