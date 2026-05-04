{{-- Admin Overview — blueprint card design (shadcn-admin style) --}}

{{-- ── Page header ────────────────────────────────────────────────────────── --}}
<div class="mb-6">
    <h1 class="text-xl font-semibold text-slate-900 leading-none">Overview</h1>
    <p class="mt-1.5 text-sm text-slate-500">Hospital-wide activity and patient enrollment status.</p>
</div>

{{-- ── Metric cards ────────────────────────────────────────────────────────── --}}
@php
    $enrollRate = $stats['active_patients'] > 0
        ? round(($stats['enrolled_patients'] / $stats['active_patients']) * 100)
        : 0;

    $cards = [
        [
            'label'   => 'Total Patients',
            'value'   => number_format($stats['total_patients']),
            'sub'     => number_format($stats['active_patients']) . ' active',
            'badge'   => null,
            'link'    => route('dashboard.patients'),
            'icon'    => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
        ],
        [
            'label'   => 'Fingerprints Enrolled',
            'value'   => number_format($stats['enrolled_patients']),
            'sub'     => 'biometrically registered',
            'badge'   => ['color' => $enrollRate >= 80 ? 'emerald' : ($enrollRate >= 50 ? 'amber' : 'red'), 'text' => $enrollRate . '%', 'dir' => $enrollRate >= 50 ? 'up' : 'down'],
            'link'    => route('dashboard.patients') . '?enrolled=1',
            'icon'    => 'M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33',
        ],
        [
            'label'   => 'Verifications Today',
            'value'   => number_format($stats['verifications_today']),
            'sub'     => number_format($stats['successful_today']) . ' successful',
            'badge'   => $stats['verifications_today'] > 0
                            ? ['color' => 'emerald', 'text' => $stats['success_rate'] . '%', 'dir' => 'up']
                            : null,
            'link'    => route('dashboard.logs'),
            'icon'    => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
        ],
        [
            'label'   => 'Pending Edit Requests',
            'value'   => number_format($stats['pending_requests']),
            'sub'     => 'awaiting review',
            'badge'   => $stats['pending_requests'] > 0
                            ? ['color' => 'amber', 'text' => 'Action needed', 'dir' => 'up']
                            : ['color' => 'emerald', 'text' => 'All clear', 'dir' => 'up'],
            'link'    => route('dashboard.edit-requests'),
            'icon'    => 'M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10',
        ],
    ];

    $badgeClasses = [
        'emerald' => 'bg-emerald-100 text-emerald-700',
        'amber'   => 'bg-amber-100 text-amber-700',
        'red'     => 'bg-red-100 text-red-700',
    ];
    $trendUp   = 'M2.25 18L9 11.25l4.306 4.307a11.95 11.95 0 015.814-5.519l2.74-1.22m0 0l-5.94-2.28m5.94 2.28l-2.28 5.941';
    $trendDown = 'M2.25 6L9 12.75l4.306-4.307a11.95 11.95 0 015.814 5.519l2.74 1.22m0 0l-5.94 2.28m5.94-2.28l-2.28-5.941';
@endphp

<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
    @foreach($cards as $card)
    <a href="{{ $card['link'] }}"
       class="group flex flex-col rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm
              transition-all duration-150 hover:shadow-md hover:border-slate-300 hover:-translate-y-px">

        {{-- Card header: icon box + label --}}
        <div class="flex items-start justify-between px-5 pt-5 pb-3">
            <div>
                <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500
                            group-hover:border-blue-200 group-hover:bg-blue-50 group-hover:text-blue-600 transition-colors">
                    <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="{{ $card['icon'] }}"/>
                    </svg>
                </div>
                <p class="mt-2.5 text-sm text-slate-500">{{ $card['label'] }}</p>
            </div>
            @if($card['badge'])
            @php $bc = $badgeClasses[$card['badge']['color']]; @endphp
            <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium {{ $bc }}">
                <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="{{ $card['badge']['dir'] === 'up' ? $trendUp : $trendDown }}"/>
                </svg>
                {{ $card['badge']['text'] }}
            </span>
            @endif
        </div>

        {{-- Card content: metric + sub --}}
        <div class="px-5 pb-5">
            <div class="text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">
                {{ $card['value'] }}
            </div>
            <p class="mt-1.5 text-xs text-slate-400">{{ $card['sub'] }}</p>
        </div>
    </a>
    @endforeach
</div>

{{-- ── Enrollment coverage card ────────────────────────────────────────────── --}}
<div class="mt-4 rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5">
    <div class="flex items-center justify-between mb-3">
        <div>
            <p class="text-sm font-semibold text-slate-800 leading-none">Enrollment Coverage</p>
            <p class="mt-1 text-xs text-slate-400">Active patients with fingerprint on file</p>
        </div>
        <span class="text-2xl font-semibold tabular-nums leading-none tracking-tight
                     {{ $enrollRate >= 80 ? 'text-emerald-600' : ($enrollRate >= 50 ? 'text-amber-600' : 'text-red-500') }}">
            {{ $enrollRate }}%
        </span>
    </div>
    <div class="h-2 w-full rounded-full bg-slate-100">
        <div class="h-2 rounded-full transition-all duration-500
                    {{ $enrollRate >= 80 ? 'bg-gradient-to-r from-emerald-400 to-emerald-500'
                        : ($enrollRate >= 50 ? 'bg-gradient-to-r from-amber-400 to-amber-500'
                        : 'bg-gradient-to-r from-red-400 to-red-500') }}"
             style="width: {{ min($enrollRate, 100) }}%"></div>
    </div>
    <div class="mt-3 flex items-center gap-4 text-xs text-slate-400">
        <span><span class="font-medium text-slate-600">{{ number_format($stats['enrolled_patients']) }}</span> enrolled</span>
        <span class="text-slate-300">·</span>
        <span><span class="font-medium text-slate-600">{{ number_format($stats['active_patients'] - $stats['enrolled_patients']) }}</span> pending</span>
        <span class="text-slate-300">·</span>
        <span><span class="font-medium text-slate-600">{{ number_format($stats['active_patients']) }}</span> active total</span>
    </div>
</div>

{{-- ── Main two-column layout ──────────────────────────────────────────────── --}}
<div class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-3">

    {{-- Recent Verifications (left 2/3) --}}
    <div class="lg:col-span-2 rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
            <div>
                <h2 class="text-sm font-semibold text-slate-900 leading-none">Recent Verifications</h2>
                <p class="mt-1 text-xs text-slate-400">Latest fingerprint scan results</p>
            </div>
            <a href="{{ route('dashboard.logs') }}"
               class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-600 shadow-sm
                      hover:bg-slate-50 hover:border-slate-300 transition-colors">
                View all
                <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"/>
                </svg>
            </a>
        </div>

        @if($recentLogs->isEmpty())
        <div class="flex flex-col items-center justify-center px-5 py-14 text-center">
            <div class="flex h-10 w-10 items-center justify-center rounded-full border border-slate-200 bg-slate-50">
                <svg class="h-5 w-5 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                </svg>
            </div>
            <p class="mt-3 text-sm font-medium text-slate-600">No verifications yet</p>
            <p class="mt-1 text-xs text-slate-400">Scan results will appear here.</p>
        </div>
        @else
        <table class="w-full text-sm">
            <thead>
                <tr class="border-b border-slate-100">
                    <th class="px-5 py-2.5 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Patient</th>
                    <th class="px-5 py-2.5 text-left text-xs font-medium text-slate-400 uppercase tracking-wide hidden sm:table-cell">Operator</th>
                    <th class="px-5 py-2.5 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Status</th>
                    <th class="px-5 py-2.5 text-right text-xs font-medium text-slate-400 uppercase tracking-wide hidden md:table-cell">Time</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @foreach($recentLogs as $log)
                @php
                    $sc = match($log->status) {
                        'matched'  => ['bg' => 'bg-emerald-100', 'text' => 'text-emerald-700', 'label' => 'Matched',  'dot' => 'bg-emerald-500'],
                        'no_match' => ['bg' => 'bg-red-100',     'text' => 'text-red-700',     'label' => 'No Match', 'dot' => 'bg-red-500'],
                        default    => ['bg' => 'bg-amber-100',   'text' => 'text-amber-700',   'label' => 'Error',    'dot' => 'bg-amber-500'],
                    };
                    $initial = strtoupper(substr($log->patient?->full_name ?? '?', 0, 1));
                @endphp
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-3.5">
                        <div class="flex items-center gap-3">
                            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full
                                        {{ $log->status === 'matched' ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-600' }}
                                        text-xs font-semibold">
                                {{ $initial }}
                            </div>
                            <span class="font-medium text-slate-800">{{ $log->patient?->full_name ?? 'Unknown patient' }}</span>
                        </div>
                    </td>
                    <td class="px-5 py-3.5 text-slate-500 hidden sm:table-cell">{{ $log->operator?->name ?? '—' }}</td>
                    <td class="px-5 py-3.5">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium {{ $sc['bg'] }} {{ $sc['text'] }}">
                            <span class="h-1.5 w-1.5 rounded-full {{ $sc['dot'] }}"></span>
                            {{ $sc['label'] }}
                        </span>
                    </td>
                    <td class="px-5 py-3.5 text-right text-xs text-slate-400 hidden md:table-cell whitespace-nowrap">
                        {{ $log->created_at->diffForHumans() }}
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
        @endif
    </div>

    {{-- Right column --}}
    <div class="space-y-4">

        {{-- Pending Edit Requests --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
                <div class="flex items-center gap-2">
                    <h2 class="text-sm font-semibold text-slate-900 leading-none">Edit Requests</h2>
                    @if($stats['pending_requests'] > 0)
                    <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700">
                        {{ $stats['pending_requests'] }}
                    </span>
                    @endif
                </div>
                <a href="{{ route('dashboard.edit-requests') }}"
                   class="text-xs font-medium text-blue-600 hover:text-blue-700 transition-colors">
                    Review →
                </a>
            </div>

            @if($pendingRequests->isEmpty())
            <div class="flex flex-col items-center justify-center px-5 py-8 text-center">
                <div class="flex h-8 w-8 items-center justify-center rounded-full border border-emerald-200 bg-emerald-50">
                    <svg class="h-4 w-4 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                    </svg>
                </div>
                <p class="mt-2 text-sm font-medium text-slate-600">All caught up</p>
                <p class="mt-0.5 text-xs text-slate-400">No pending requests.</p>
            </div>
            @else
            <ul class="divide-y divide-slate-100">
                @foreach($pendingRequests as $req)
                <li class="px-5 py-3.5">
                    <p class="text-sm font-medium text-slate-800 truncate">{{ $req->patient?->full_name ?? '—' }}</p>
                    <p class="mt-0.5 text-xs text-slate-500">
                        <span class="font-medium text-slate-700 capitalize">{{ str_replace('_', ' ', $req->field_name) }}</span>
                        <span class="text-slate-300 mx-1">·</span>
                        by {{ $req->requestedBy?->name ?? '—' }}
                    </p>
                    <div class="mt-2 flex gap-1.5">
                        <form method="POST" action="{{ route('dashboard.edit-requests.approve', $req->id) }}" class="flex-1">
                            @csrf
                            <button type="submit"
                                    class="w-full rounded-lg border border-emerald-200 bg-emerald-50 px-2 py-1.5 text-xs font-medium text-emerald-700
                                           hover:bg-emerald-100 transition-colors">
                                Approve
                            </button>
                        </form>
                        <form method="POST" action="{{ route('dashboard.edit-requests.reject', $req->id) }}" class="flex-1">
                            @csrf
                            <button type="submit"
                                    class="w-full rounded-lg border border-red-200 bg-red-50 px-2 py-1.5 text-xs font-medium text-red-700
                                           hover:bg-red-100 transition-colors">
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
        <div class="rounded-xl border border-amber-200 bg-gradient-to-t from-amber-50/60 to-white shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-amber-200/70">
                <div class="flex items-center gap-2">
                    <div class="flex h-6 w-6 items-center justify-center rounded-lg border border-amber-200 bg-amber-50">
                        <svg class="h-3.5 w-3.5 text-amber-600" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
                        </svg>
                    </div>
                    <h2 class="text-sm font-semibold text-amber-900 leading-none">Locked Fingerprints</h2>
                </div>
                <span class="inline-flex items-center rounded-full bg-amber-200 px-2 py-0.5 text-xs font-bold text-amber-800">
                    {{ $stats['locked_fingerprints'] }}
                </span>
            </div>
            <ul class="divide-y divide-amber-100/70">
                @foreach($lockedFingerprints as $fp)
                <li class="px-5 py-3">
                    <p class="text-sm font-medium text-amber-900">{{ $fp->patient?->full_name ?? '—' }}</p>
                    <p class="mt-0.5 text-xs text-amber-700">
                        {{ $fp->failed_attempts }} failed
                        <span class="text-amber-400 mx-1">·</span>
                        locked {{ $fp->locked_at?->diffForHumans() }}
                    </p>
                </li>
                @endforeach
                @if($stats['locked_fingerprints'] > 3)
                <li class="px-5 py-3">
                    <p class="text-xs font-medium text-amber-700">
                        + {{ $stats['locked_fingerprints'] - 3 }} more — unlock via Patients.
                    </p>
                </li>
                @endif
            </ul>
        </div>
        @endif

        {{-- New Patients --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900 leading-none">New Patients</h2>
                <a href="{{ route('dashboard.patients') }}"
                   class="text-xs font-medium text-blue-600 hover:text-blue-700 transition-colors">
                    View all →
                </a>
            </div>

            @if($recentPatients->isEmpty())
            <div class="px-5 py-8 text-center">
                <p class="text-sm text-slate-400">No patients registered yet.</p>
            </div>
            @else
            <ul class="divide-y divide-slate-100">
                @foreach($recentPatients as $patient)
                <li>
                    <a href="{{ route('dashboard.patients.show', $patient) }}"
                       class="flex items-center gap-3 px-5 py-3 hover:bg-slate-50/60 transition-colors group">
                        <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-100
                                    text-xs font-semibold text-blue-700 group-hover:bg-blue-200 transition-colors">
                            {{ strtoupper(substr($patient->full_name, 0, 1)) }}
                        </div>
                        <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-slate-800 truncate group-hover:text-blue-600 transition-colors">
                                {{ $patient->full_name }}
                            </p>
                            <p class="text-xs text-slate-400">{{ $patient->created_at->format('d M Y') }}</p>
                        </div>
                        @if($patient->isEnrolled())
                        <span class="h-2 w-2 shrink-0 rounded-full bg-emerald-500" title="Enrolled"></span>
                        @else
                        <span class="h-2 w-2 shrink-0 rounded-full bg-slate-300" title="Not enrolled"></span>
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
<div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">

    <div class="rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">30-day success rate</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">
            {{ $stats['success_rate'] }}%
        </div>
    </div>

    <div class="rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">Verifications this week</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">
            {{ number_format($stats['verifications_week']) }}
        </div>
    </div>

    <a href="{{ route('dashboard.users') }}"
       class="group rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5
              hover:shadow-md hover:border-slate-300 hover:-translate-y-px transition-all duration-150">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500
                    group-hover:border-blue-200 group-hover:bg-blue-50 group-hover:text-blue-600 transition-colors">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">Active staff members</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight group-hover:text-blue-600 transition-colors">
            {{ number_format($stats['total_staff']) }}
        </div>
    </a>

</div>
