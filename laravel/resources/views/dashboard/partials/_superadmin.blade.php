{{-- Super Admin Overview — blueprint card design (shadcn-admin style) --}}

{{-- ── Page header ────────────────────────────────────────────────────────── --}}
<div class="mb-6">
    <h1 class="text-xl font-semibold text-slate-900 leading-none">System Overview</h1>
    <p class="mt-1.5 text-sm text-slate-500">Cross-hospital activity, enrollment health, and audit trail.</p>
</div>

{{-- ── Metric cards ────────────────────────────────────────────────────────── --}}
@php
    $globalEnrollRate = $stats['total_patients'] > 0
        ? round(($stats['total_enrolled'] / $stats['total_patients']) * 100) : 0;

    $trendUp   = 'M2.25 18L9 11.25l4.306 4.307a11.95 11.95 0 015.814-5.519l2.74-1.22m0 0l-5.94-2.28m5.94 2.28l-2.28 5.941';
    $trendDown = 'M2.25 6L9 12.75l4.306-4.307a11.95 11.95 0 015.814 5.519l2.74 1.22m0 0l-5.94 2.28m5.94-2.28l-2.28-5.941';

    $metricCards = [
        [
            'label' => 'Active Hospitals',
            'value' => number_format($stats['total_hospitals']),
            'sub'   => 'registered facilities',
            'badge' => null,
            'link'  => null,
            'icon'  => 'M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21',
        ],
        [
            'label' => 'Total Patients',
            'value' => number_format($stats['total_patients']),
            'sub'   => number_format($stats['total_enrolled']) . ' enrolled system-wide',
            'badge' => ['color' => $globalEnrollRate >= 80 ? 'emerald' : ($globalEnrollRate >= 50 ? 'amber' : 'red'), 'text' => $globalEnrollRate . '%', 'dir' => $globalEnrollRate >= 50 ? 'up' : 'down'],
            'link'  => route('dashboard.patients'),
            'icon'  => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
        ],
        [
            'label' => 'Verifications Today',
            'value' => number_format($stats['verifications_today']),
            'sub'   => number_format($stats['successful_today']) . ' successful',
            'badge' => $stats['verifications_today'] > 0
                        ? ['color' => 'emerald', 'text' => $stats['success_rate'] . '%', 'dir' => 'up']
                        : null,
            'link'  => route('dashboard.logs'),
            'icon'  => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
        ],
        [
            'label' => 'Pending Edit Requests',
            'value' => number_format($stats['pending_requests']),
            'sub'   => 'across all hospitals',
            'badge' => $stats['pending_requests'] > 0
                        ? ['color' => 'amber', 'text' => 'Action needed', 'dir' => 'up']
                        : ['color' => 'emerald', 'text' => 'All clear', 'dir' => 'up'],
            'link'  => route('dashboard.edit-requests'),
            'icon'  => 'M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10',
        ],
    ];

    $badgeClasses = [
        'emerald' => 'bg-emerald-100 text-emerald-700',
        'amber'   => 'bg-amber-100 text-amber-700',
        'red'     => 'bg-red-100 text-red-700',
    ];
@endphp

<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
    @foreach($metricCards as $card)
    @php $tag = $card['link'] ? 'a' : 'div'; @endphp
    <{{ $tag }} @if($card['link']) href="{{ $card['link'] }}" @endif
       class="group flex flex-col rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm
              {{ $card['link'] ? 'transition-all duration-150 hover:shadow-md hover:border-slate-300 hover:-translate-y-px' : '' }}">

        <div class="flex items-start justify-between px-5 pt-5 pb-3">
            <div>
                <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500
                            {{ $card['link'] ? 'group-hover:border-blue-200 group-hover:bg-blue-50 group-hover:text-blue-600 transition-colors' : '' }}">
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

        <div class="px-5 pb-5">
            <div class="text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight
                        {{ $card['link'] ? 'group-hover:text-blue-600 transition-colors' : '' }}">
                {{ $card['value'] }}
            </div>
            <p class="mt-1.5 text-xs text-slate-400">{{ $card['sub'] }}</p>
        </div>
    </{{ $tag }}>
    @endforeach
</div>

{{-- ── Secondary stats ─────────────────────────────────────────────────────── --}}
<div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">

    <div class="rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">System-wide success rate</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">
            {{ $stats['success_rate'] }}%
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
        <p class="mt-2.5 text-sm text-slate-500">Total active staff</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight group-hover:text-blue-600 transition-colors">
            {{ number_format($stats['total_staff']) }}
        </div>
    </a>

    <div class="rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm p-5">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">Global enrollment coverage</p>
        <div class="mt-1 text-3xl font-semibold tabular-nums leading-none tracking-tight
                    {{ $globalEnrollRate >= 80 ? 'text-emerald-600' : ($globalEnrollRate >= 50 ? 'text-amber-600' : 'text-red-500') }}">
            {{ $globalEnrollRate }}%
        </div>
    </div>

</div>

{{-- ── Hospital Health Table ───────────────────────────────────────────────── --}}
<div class="mt-4 rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
        <div>
            <h2 class="text-sm font-semibold text-slate-900 leading-none">Hospital Health</h2>
            <p class="mt-1 text-xs text-slate-400">Per-facility breakdown — enrollment, verifications, and alerts</p>
        </div>
        <span class="inline-flex items-center rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1 text-xs font-medium text-slate-500">
            {{ $hospitalStats->count() }} hospitals
        </span>
    </div>

    @if($hospitalStats->isEmpty())
    <div class="flex flex-col items-center justify-center px-5 py-14 text-center">
        <div class="flex h-10 w-10 items-center justify-center rounded-full border border-slate-200 bg-slate-50">
            <svg class="h-5 w-5 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18"/>
            </svg>
        </div>
        <p class="mt-3 text-sm font-medium text-slate-600">No hospitals found</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead>
                <tr class="border-b border-slate-100 bg-slate-50/60">
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Hospital</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Patients</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Enrolled</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Verif. Today</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Staff</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Pending</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Locked FPs</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @foreach($hospitalStats as $h)
                @php
                    $enroll    = $h['patients'] > 0 ? round(($h['enrolled'] / $h['patients']) * 100) : 0;
                    $matchRate = $h['ver_today'] > 0 ? round(($h['success_today'] / $h['ver_today']) * 100) : null;
                    $initial   = strtoupper(substr($h['name'], 0, 1));
                @endphp
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-3.5">
                        <div class="flex items-center gap-3">
                            <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-slate-50
                                        text-xs font-semibold text-slate-600">
                                {{ $initial }}
                            </div>
                            <div>
                                <p class="font-medium text-slate-800">{{ $h['name'] }}</p>
                                <p class="text-xs text-slate-400">{{ $h['city'] }}</p>
                            </div>
                        </div>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="font-semibold text-slate-800 tabular-nums">{{ number_format($h['patients']) }}</span>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="font-semibold tabular-nums {{ $enroll >= 80 ? 'text-emerald-600' : ($enroll >= 50 ? 'text-amber-600' : 'text-red-500') }}">
                            {{ $enroll }}%
                        </span>
                        <span class="block text-xs text-slate-400 tabular-nums">{{ number_format($h['enrolled']) }} pts</span>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="font-semibold text-slate-800 tabular-nums">{{ number_format($h['ver_today']) }}</span>
                        @if($matchRate !== null)
                        <span class="block text-xs tabular-nums {{ $matchRate >= 80 ? 'text-emerald-600' : 'text-amber-600' }}">{{ $matchRate }}% match</span>
                        @endif
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="text-slate-600 tabular-nums">{{ number_format($h['staff']) }}</span>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        @if($h['pending_requests'] > 0)
                        <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                            {{ $h['pending_requests'] }}
                        </span>
                        @else
                        <span class="text-xs text-slate-300">—</span>
                        @endif
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        @if($h['locked_fps'] > 0)
                        <span class="inline-flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                            <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
                            </svg>
                            {{ $h['locked_fps'] }}
                        </span>
                        @else
                        <span class="text-xs text-slate-300">—</span>
                        @endif
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>
    @endif
</div>

{{-- ── Recent System Activity ──────────────────────────────────────────────── --}}
<div class="mt-4 rounded-xl border border-slate-200 bg-white shadow-sm">
    <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
        <div>
            <h2 class="text-sm font-semibold text-slate-900 leading-none">Recent System Activity</h2>
            <p class="mt-1 text-xs text-slate-400">Latest audit log entries across all hospitals</p>
        </div>
        <a href="{{ route('dashboard.audit-logs') }}"
           class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-600 shadow-sm
                  hover:bg-slate-50 hover:border-slate-300 transition-colors">
            Full audit log
            <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"/>
            </svg>
        </a>
    </div>

    @if(isset($recentAudit) && $recentAudit->isNotEmpty())
    <ul class="divide-y divide-slate-100">
        @foreach($recentAudit as $entry)
        <li class="flex items-center gap-4 px-5 py-3.5 hover:bg-slate-50/60 transition-colors">
            <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-slate-200 bg-slate-50 text-slate-400">
                <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z"/>
                </svg>
            </div>
            <div class="flex-1 min-w-0">
                <p class="text-sm text-slate-700 truncate">
                    <span class="font-medium text-slate-800">{{ $entry->staff?->name ?? 'System' }}</span>
                    <span class="text-slate-400 mx-1">·</span>
                    <span class="font-mono text-xs bg-slate-100 px-1.5 py-0.5 rounded text-slate-600">{{ $entry->action }}</span>
                </p>
            </div>
            <p class="shrink-0 text-xs text-slate-400 whitespace-nowrap">{{ $entry->created_at->diffForHumans() }}</p>
        </li>
        @endforeach
    </ul>
    @else
    <div class="flex flex-col items-center justify-center px-5 py-14 text-center">
        <div class="flex h-10 w-10 items-center justify-center rounded-full border border-slate-200 bg-slate-50">
            <svg class="h-5 w-5 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/>
            </svg>
        </div>
        <p class="mt-3 text-sm font-medium text-slate-600">No recent activity</p>
        <p class="mt-1 text-xs text-slate-400">Audit entries will appear here.</p>
    </div>
    @endif
</div>
