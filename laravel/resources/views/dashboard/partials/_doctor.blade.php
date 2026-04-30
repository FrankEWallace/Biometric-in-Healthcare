{{-- Doctor Overview — patient-centric, read-only, no scores --}}

{{-- ── Read-only notice ────────────────────────────────────────────────────── --}}
<div class="mb-6 flex items-start gap-3 rounded-xl border border-sky-200 bg-sky-50 p-4">
    <svg class="h-5 w-5 text-sky-600 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round"
              d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z"/>
    </svg>
    <div>
        <p class="text-sm font-semibold text-sky-800">Clinical Read Access</p>
        <p class="text-xs text-sky-700 mt-0.5">
            You have read-only access to patient and verification data within your hospital.
            EHR and insurance information becomes available after a successful fingerprint verification on the mobile app.
        </p>
    </div>
</div>

{{-- ── Stat cards ──────────────────────────────────────────────────────────── --}}
<div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <p class="text-xs font-medium text-slate-500 uppercase tracking-wide">Active Patients</p>
        <p class="mt-2 text-3xl font-bold text-slate-900">{{ number_format($stats['active_patients']) }}</p>
        <a href="{{ route('dashboard.patients') }}" class="mt-2 block text-xs font-medium text-blue-600 hover:text-blue-700">
            Browse patients →
        </a>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <p class="text-xs font-medium text-slate-500 uppercase tracking-wide">Verifications Today</p>
        <p class="mt-2 text-3xl font-bold text-slate-900">{{ number_format($stats['verifications_today']) }}</p>
        <p class="mt-1 text-xs text-slate-400">{{ number_format($stats['successful_today']) }} successful</p>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <p class="text-xs font-medium text-slate-500 uppercase tracking-wide">Success Rate Today</p>
        @php
            $rate = $stats['verifications_today'] > 0
                ? (int) round(($stats['successful_today'] / $stats['verifications_today']) * 100) : 0;
        @endphp
        <p class="mt-2 text-3xl font-bold {{ $rate >= 80 ? 'text-emerald-600' : ($rate >= 50 ? 'text-amber-600' : 'text-slate-900') }}">
            {{ $stats['verifications_today'] > 0 ? $rate . '%' : '—' }}
        </p>
        <p class="mt-1 text-xs text-slate-400">match rate</p>
    </div>
</div>

{{-- ── Recent Verifications (no score for doctors) ────────────────────────── --}}
<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">

    <div class="lg:col-span-2 rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
            <h2 class="text-sm font-semibold text-slate-800">Recent Verifications</h2>
            <a href="{{ route('dashboard.logs') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">View all →</a>
        </div>

        @if($recentLogs->isEmpty())
        <div class="px-5 py-12 text-center">
            <svg class="mx-auto h-10 w-10 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round"
                      d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
            </svg>
            <p class="mt-3 text-sm text-slate-400">No verification logs yet.</p>
        </div>
        @else
        <ul class="divide-y divide-slate-100">
            @foreach($recentLogs as $log)
            @php
                $sc = match($log->status) {
                    'matched'  => ['bg' => 'bg-emerald-100', 'text' => 'text-emerald-700', 'label' => 'Matched'],
                    'no_match' => ['bg' => 'bg-red-100',     'text' => 'text-red-700',     'label' => 'No Match'],
                    default    => ['bg' => 'bg-amber-100',   'text' => 'text-amber-700',   'label' => 'Error'],
                };
            @endphp
            <li class="flex items-center gap-4 px-5 py-3.5">
                <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full {{ $log->status === 'matched' ? 'bg-emerald-100' : 'bg-red-100' }}">
                    @if($log->status === 'matched')
                    <svg class="h-4 w-4 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                    </svg>
                    @else
                    <svg class="h-4 w-4 text-red-500" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
                    </svg>
                    @endif
                </div>
                <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-slate-800 truncate">
                        {{ $log->patient?->full_name ?? 'Unknown patient' }}
                    </p>
                    <p class="text-xs text-slate-400">
                        Verified by {{ $log->operator?->name ?? '—' }}
                    </p>
                </div>
                <div class="text-right shrink-0">
                    <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $sc['bg'] }} {{ $sc['text'] }}">
                        {{ $sc['label'] }}
                    </span>
                    <p class="mt-0.5 text-xs text-slate-400">{{ $log->created_at->diffForHumans() }}</p>
                </div>
            </li>
            @endforeach
        </ul>
        @endif
    </div>

    {{-- Patient search hint --}}
    <div class="space-y-4">
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm p-5">
            <h3 class="text-sm font-semibold text-slate-800 mb-3">Find a Patient</h3>
            <form method="GET" action="{{ route('dashboard.patients') }}">
                <div class="relative">
                    <svg class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"/>
                    </svg>
                    <input type="text" name="search" placeholder="Name or JMBG…"
                           class="w-full rounded-lg border border-slate-200 bg-slate-50 pl-9 pr-4 py-2.5 text-sm text-slate-800 placeholder-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
                </div>
                <button type="submit"
                        class="mt-3 w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 transition-colors">
                    Search Patients
                </button>
            </form>
        </div>

        <div class="rounded-xl border border-slate-200 bg-white shadow-sm p-5">
            <h3 class="text-sm font-semibold text-slate-800 mb-3">Quick Links</h3>
            <div class="space-y-2">
                <a href="{{ route('dashboard.patients') }}"
                   class="flex items-center justify-between rounded-lg px-3 py-2.5 text-sm text-slate-700 hover:bg-slate-50 transition-colors group">
                    All Patients
                    <svg class="h-4 w-4 text-slate-400 group-hover:text-slate-600" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5"/>
                    </svg>
                </a>
                <a href="{{ route('dashboard.patients') }}?enrolled=1"
                   class="flex items-center justify-between rounded-lg px-3 py-2.5 text-sm text-slate-700 hover:bg-slate-50 transition-colors group">
                    Enrolled Patients
                    <svg class="h-4 w-4 text-slate-400 group-hover:text-slate-600" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5"/>
                    </svg>
                </a>
                <a href="{{ route('dashboard.logs') }}"
                   class="flex items-center justify-between rounded-lg px-3 py-2.5 text-sm text-slate-700 hover:bg-slate-50 transition-colors group">
                    Verification Logs
                    <svg class="h-4 w-4 text-slate-400 group-hover:text-slate-600" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5"/>
                    </svg>
                </a>
            </div>
        </div>
    </div>
</div>
