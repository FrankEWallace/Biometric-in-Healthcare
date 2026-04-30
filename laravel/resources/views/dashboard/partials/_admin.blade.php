{{-- Admin Overview — hospital-scoped stats + edit requests + locked fingerprints --}}

{{-- ── Stat cards ────────────────────────────────────────────────────────── --}}
<div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
    @php
        $cards = [
            ['label' => 'Total Patients',       'value' => number_format($stats['total_patients']),      'sub' => number_format($stats['active_patients']) . ' active',         'color' => 'blue',   'link' => route('dashboard.patients'),
             'icon' => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z'],
            ['label' => 'Fingerprints Enrolled', 'value' => number_format($stats['enrolled_patients']),  'sub' => 'patients biometrically enrolled',                              'color' => 'violet', 'link' => route('dashboard.patients') . '?enrolled=1',
             'icon' => 'M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33'],
            ['label' => 'Verifications Today',  'value' => number_format($stats['verifications_today']), 'sub' => number_format($stats['successful_today']) . ' successful',      'color' => 'emerald','link' => route('dashboard.logs'),
             'icon' => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z'],
            ['label' => 'Pending Edit Requests','value' => number_format($stats['pending_requests']),    'sub' => 'awaiting review',                                              'color' => $stats['pending_requests'] > 0 ? 'amber' : 'slate', 'link' => route('dashboard.edit-requests'),
             'icon' => 'M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10'],
        ];
        $colorMap = [
            'blue'   => ['bg' => 'bg-blue-50',    'icon' => 'text-blue-600',    'ring' => 'ring-blue-100'],
            'violet' => ['bg' => 'bg-violet-50',  'icon' => 'text-violet-600',  'ring' => 'ring-violet-100'],
            'emerald'=> ['bg' => 'bg-emerald-50', 'icon' => 'text-emerald-600', 'ring' => 'ring-emerald-100'],
            'amber'  => ['bg' => 'bg-amber-50',   'icon' => 'text-amber-600',   'ring' => 'ring-amber-100'],
            'slate'  => ['bg' => 'bg-slate-50',   'icon' => 'text-slate-400',   'ring' => 'ring-slate-200'],
        ];
    @endphp

    @foreach($cards as $card)
    @php $c = $colorMap[$card['color']]; @endphp
    <a href="{{ $card['link'] }}"
       class="group block rounded-xl border border-slate-200 bg-white p-5 shadow-sm transition-all duration-150
              hover:shadow-md hover:border-slate-300 hover:-translate-y-0.5">
        <div class="flex items-start justify-between">
            <div class="flex-1 min-w-0">
                <p class="text-xs font-medium text-slate-500 uppercase tracking-wide">{{ $card['label'] }}</p>
                <p class="mt-2 text-2xl font-bold text-slate-900">{{ $card['value'] }}</p>
                <p class="mt-1 text-xs text-slate-400">{{ $card['sub'] }}</p>
            </div>
            <div class="{{ $c['bg'] }} {{ $c['ring'] }} ring-1 rounded-lg p-2.5 ml-3 shrink-0">
                <svg class="h-5 w-5 {{ $c['icon'] }}" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="{{ $card['icon'] }}"/>
                </svg>
            </div>
        </div>
        <p class="mt-3 text-xs font-medium text-blue-500 opacity-0 group-hover:opacity-100 transition-opacity">View details →</p>
    </a>
    @endforeach
</div>

{{-- ── Enrollment progress bar ────────────────────────────────────────────── --}}
@php
    $enrollRate = $stats['active_patients'] > 0
        ? round(($stats['enrolled_patients'] / $stats['active_patients']) * 100)
        : 0;
@endphp
<div class="mt-4 rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
    <div class="flex items-center justify-between mb-3">
        <p class="text-sm font-semibold text-slate-700">Enrollment Coverage</p>
        <span class="text-sm font-bold {{ $enrollRate >= 80 ? 'text-emerald-600' : ($enrollRate >= 50 ? 'text-amber-600' : 'text-red-500') }}">
            {{ $enrollRate }}%
        </span>
    </div>
    <div class="h-2.5 w-full rounded-full bg-slate-100">
        <div class="h-2.5 rounded-full transition-all duration-500
                    {{ $enrollRate >= 80 ? 'bg-gradient-to-r from-emerald-400 to-emerald-500' : ($enrollRate >= 50 ? 'bg-gradient-to-r from-amber-400 to-amber-500' : 'bg-gradient-to-r from-red-400 to-red-500') }}"
             style="width: {{ min($enrollRate, 100) }}%"></div>
    </div>
    <p class="mt-2 text-xs text-slate-400">
        {{ number_format($stats['enrolled_patients']) }} of {{ number_format($stats['active_patients']) }} active patients have fingerprints enrolled
    </p>
</div>

{{-- ── Two-column layout ───────────────────────────────────────────────────── --}}
<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">

    {{-- Recent Verifications (left 2/3) --}}
    <div class="lg:col-span-2 rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
            <h2 class="text-sm font-semibold text-slate-800">Recent Verifications</h2>
            <a href="{{ route('dashboard.logs') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">View all →</a>
        </div>
        @if($recentLogs->isEmpty())
        <div class="px-5 py-12 text-center">
            <svg class="mx-auto h-10 w-10 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
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
                    <p class="text-sm font-medium text-slate-800 truncate">{{ $log->patient?->full_name ?? 'Unknown patient' }}</p>
                    <p class="text-xs text-slate-400">by {{ $log->operator?->name ?? '—' }}</p>
                </div>
                <div class="text-right shrink-0">
                    <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $sc['bg'] }} {{ $sc['text'] }}">{{ $sc['label'] }}</span>
                    <p class="mt-0.5 text-xs text-slate-400">{{ $log->created_at->diffForHumans() }}</p>
                </div>
            </li>
            @endforeach
        </ul>
        @endif
    </div>

    {{-- Right column: Edit Requests + New Patients --}}
    <div class="space-y-4">

        {{-- Pending Edit Requests --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-800">Pending Edit Requests</h2>
                <a href="{{ route('dashboard.edit-requests') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">
                    Review all →
                </a>
            </div>
            @if($pendingRequests->isEmpty())
            <div class="px-5 py-8 text-center">
                <svg class="mx-auto h-8 w-8 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                </svg>
                <p class="mt-2 text-sm text-slate-400">All caught up.</p>
            </div>
            @else
            <ul class="divide-y divide-slate-100">
                @foreach($pendingRequests as $req)
                <li class="px-5 py-3.5">
                    <p class="text-sm font-medium text-slate-800 truncate">{{ $req->patient?->full_name ?? '—' }}</p>
                    <p class="text-xs text-slate-500 mt-0.5">
                        <span class="font-medium capitalize">{{ str_replace('_', ' ', $req->field_name) }}</span>
                        · by {{ $req->requestedBy?->name ?? '—' }}
                    </p>
                    <div class="mt-2 flex gap-2">
                        <form method="POST" action="{{ route('dashboard.edit-requests.approve', $req->id) }}" class="flex-1">
                            @csrf
                            <button type="submit"
                                    class="w-full rounded-lg bg-emerald-50 border border-emerald-200 px-2 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-100 transition-colors">
                                Approve
                            </button>
                        </form>
                        <form method="POST" action="{{ route('dashboard.edit-requests.reject', $req->id) }}" class="flex-1">
                            @csrf
                            <button type="submit"
                                    class="w-full rounded-lg bg-red-50 border border-red-200 px-2 py-1 text-xs font-medium text-red-700 hover:bg-red-100 transition-colors">
                                Reject
                            </button>
                        </form>
                    </div>
                </li>
                @endforeach
            </ul>
            @endif
        </div>

        {{-- Locked Fingerprints --}}
        @if($stats['locked_fingerprints'] > 0)
        <div class="rounded-xl border border-amber-200 bg-amber-50 shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-amber-200">
                <div class="flex items-center gap-2">
                    <svg class="h-4 w-4 text-amber-600" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
                    </svg>
                    <h2 class="text-sm font-semibold text-amber-800">Locked Fingerprints</h2>
                </div>
                <span class="text-xs font-bold text-amber-700 bg-amber-200 rounded-full px-2 py-0.5">
                    {{ $stats['locked_fingerprints'] }}
                </span>
            </div>
            @foreach($lockedFingerprints as $fp)
            <div class="px-5 py-3 border-b border-amber-200/60 last:border-0">
                <p class="text-sm font-medium text-amber-900">{{ $fp->patient?->full_name ?? '—' }}</p>
                <p class="text-xs text-amber-700 mt-0.5">
                    Locked {{ $fp->locked_at?->diffForHumans() }}
                    · {{ $fp->failed_attempts }} failed attempts
                </p>
            </div>
            @endforeach
            @if($stats['locked_fingerprints'] > 3)
            <div class="px-5 py-3">
                <p class="text-xs text-amber-700 font-medium">+ {{ $stats['locked_fingerprints'] - 3 }} more locked — unlock via Patients list.</p>
            </div>
            @endif
        </div>
        @endif

        {{-- Recently registered patients --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-800">New Patients</h2>
                <a href="{{ route('dashboard.patients') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">View all →</a>
            </div>
            @if($recentPatients->isEmpty())
            <div class="px-5 py-8 text-center">
                <p class="text-sm text-slate-400">No patients registered yet.</p>
            </div>
            @else
            <ul class="divide-y divide-slate-100">
                @foreach($recentPatients as $patient)
                <li class="px-5 py-3">
                    <a href="{{ route('dashboard.patients.show', $patient) }}" class="flex items-center gap-3 group">
                        <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xs font-semibold text-blue-700">
                            {{ strtoupper(substr($patient->full_name, 0, 1)) }}
                        </div>
                        <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-slate-800 group-hover:text-blue-600 truncate transition-colors">
                                {{ $patient->full_name }}
                            </p>
                            <p class="text-xs text-slate-400">{{ $patient->created_at->format('d M Y') }}</p>
                        </div>
                        @if($patient->isEnrolled())
                        <span class="shrink-0 h-2 w-2 rounded-full bg-emerald-500" title="Enrolled"></span>
                        @else
                        <span class="shrink-0 h-2 w-2 rounded-full bg-slate-300" title="Not enrolled"></span>
                        @endif
                    </a>
                </li>
                @endforeach
            </ul>
            @endif
        </div>
    </div>
</div>

{{-- ── Bottom stats row ────────────────────────────────────────────────────── --}}
<div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        <p class="text-3xl font-bold text-slate-900">{{ $stats['success_rate'] }}%</p>
        <p class="mt-1 text-sm text-slate-500">30-day success rate</p>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        <p class="text-3xl font-bold text-slate-900">{{ number_format($stats['verifications_week']) }}</p>
        <p class="mt-1 text-sm text-slate-500">Verifications this week</p>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        <p class="text-3xl font-bold text-slate-900">{{ number_format($stats['total_staff']) }}</p>
        <p class="mt-1 text-sm text-slate-500">
            <a href="{{ route('dashboard.users') }}" class="hover:text-blue-600 transition-colors">Active staff members</a>
        </p>
    </div>
</div>
