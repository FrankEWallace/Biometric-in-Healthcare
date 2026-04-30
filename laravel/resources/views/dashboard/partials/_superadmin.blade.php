{{-- Super Admin Overview — cross-hospital system view --}}

{{-- ── System-wide stat cards ──────────────────────────────────────────────── --}}
<div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
    @php
        $cards = [
            ['label' => 'Active Hospitals',      'value' => number_format($stats['total_hospitals']),     'sub' => 'registered facilities',                                        'color' => 'indigo',
             'icon' => 'M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21'],
            ['label' => 'Total Patients',        'value' => number_format($stats['total_patients']),      'sub' => number_format($stats['total_enrolled']) . ' enrolled',           'color' => 'blue',
             'icon' => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z'],
            ['label' => 'Verifications Today',   'value' => number_format($stats['verifications_today']), 'sub' => number_format($stats['successful_today']) . ' successful',       'color' => 'emerald',
             'icon' => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z'],
            ['label' => 'Pending Edit Requests', 'value' => number_format($stats['pending_requests']),    'sub' => 'across all hospitals',                                          'color' => $stats['pending_requests'] > 0 ? 'amber' : 'slate',
             'icon' => 'M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10'],
        ];
        $colorMap = [
            'indigo' => ['bg' => 'bg-indigo-50',  'icon' => 'text-indigo-600',  'ring' => 'ring-indigo-100'],
            'blue'   => ['bg' => 'bg-blue-50',    'icon' => 'text-blue-600',    'ring' => 'ring-blue-100'],
            'emerald'=> ['bg' => 'bg-emerald-50', 'icon' => 'text-emerald-600', 'ring' => 'ring-emerald-100'],
            'amber'  => ['bg' => 'bg-amber-50',   'icon' => 'text-amber-600',   'ring' => 'ring-amber-100'],
            'slate'  => ['bg' => 'bg-slate-50',   'icon' => 'text-slate-400',   'ring' => 'ring-slate-200'],
        ];
    @endphp

    @foreach($cards as $card)
    @php $c = $colorMap[$card['color']]; @endphp
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
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
    </div>
    @endforeach
</div>

{{-- ── Secondary stats ─────────────────────────────────────────────────────── --}}
<div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        <p class="text-3xl font-bold text-slate-900">{{ $stats['success_rate'] }}%</p>
        <p class="mt-1 text-sm text-slate-500">System-wide success rate today</p>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        <p class="text-3xl font-bold text-slate-900">{{ number_format($stats['total_staff']) }}</p>
        <p class="mt-1 text-sm text-slate-500">
            <a href="{{ route('dashboard.users') }}" class="hover:text-blue-600 transition-colors">Total active staff</a>
        </p>
    </div>
    <div class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm text-center">
        @php
            $globalEnrollRate = $stats['total_patients'] > 0
                ? round(($stats['total_enrolled'] / $stats['total_patients']) * 100) : 0;
        @endphp
        <p class="text-3xl font-bold {{ $globalEnrollRate >= 80 ? 'text-emerald-600' : ($globalEnrollRate >= 50 ? 'text-amber-600' : 'text-red-500') }}">
            {{ $globalEnrollRate }}%
        </p>
        <p class="mt-1 text-sm text-slate-500">Global enrollment coverage</p>
    </div>
</div>

{{-- ── Hospital Health Table ───────────────────────────────────────────────── --}}
<div class="mt-6 rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    <div class="flex items-center justify-between px-6 py-4 border-b border-slate-100">
        <h2 class="text-sm font-semibold text-slate-800">Hospital Health Overview</h2>
        <span class="text-xs text-slate-400">{{ $hospitalStats->count() }} hospitals</span>
    </div>

    @if($hospitalStats->isEmpty())
    <div class="px-6 py-12 text-center">
        <p class="text-sm text-slate-400">No hospitals found.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead class="bg-slate-50">
                <tr>
                    <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Hospital</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Patients</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Enrolled</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Verif. Today</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Staff</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Pending</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Locked FPs</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 bg-white">
                @foreach($hospitalStats as $h)
                @php
                    $enroll = $h['patients'] > 0 ? round(($h['enrolled'] / $h['patients']) * 100) : 0;
                    $matchRate = $h['ver_today'] > 0 ? round(($h['success_today'] / $h['ver_today']) * 100) : null;
                @endphp
                <tr class="hover:bg-slate-50 transition-colors">
                    <td class="px-6 py-4">
                        <p class="text-sm font-medium text-slate-800">{{ $h['name'] }}</p>
                        <p class="text-xs text-slate-400">{{ $h['city'] }}</p>
                    </td>
                    <td class="px-4 py-4 text-right">
                        <span class="text-sm font-semibold text-slate-800">{{ number_format($h['patients']) }}</span>
                    </td>
                    <td class="px-4 py-4 text-right">
                        <div class="flex flex-col items-end gap-1">
                            <span class="text-sm font-semibold {{ $enroll >= 80 ? 'text-emerald-600' : ($enroll >= 50 ? 'text-amber-600' : 'text-red-500') }}">
                                {{ $enroll }}%
                            </span>
                            <span class="text-xs text-slate-400">{{ number_format($h['enrolled']) }} pts</span>
                        </div>
                    </td>
                    <td class="px-4 py-4 text-right">
                        <span class="text-sm font-semibold text-slate-800">{{ number_format($h['ver_today']) }}</span>
                        @if($matchRate !== null)
                        <span class="block text-xs {{ $matchRate >= 80 ? 'text-emerald-600' : 'text-amber-600' }}">{{ $matchRate }}% match</span>
                        @endif
                    </td>
                    <td class="px-4 py-4 text-right">
                        <span class="text-sm text-slate-600">{{ number_format($h['staff']) }}</span>
                    </td>
                    <td class="px-4 py-4 text-right">
                        @if($h['pending_requests'] > 0)
                        <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                            {{ $h['pending_requests'] }}
                        </span>
                        @else
                        <span class="text-xs text-slate-400">—</span>
                        @endif
                    </td>
                    <td class="px-4 py-4 text-right">
                        @if($h['locked_fps'] > 0)
                        <span class="inline-flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                            <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
                            </svg>
                            {{ $h['locked_fps'] }}
                        </span>
                        @else
                        <span class="text-xs text-slate-400">—</span>
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
<div class="mt-6 rounded-xl border border-slate-200 bg-white shadow-sm">
    <div class="flex items-center justify-between px-6 py-4 border-b border-slate-100">
        <h2 class="text-sm font-semibold text-slate-800">Recent System Activity</h2>
        <a href="{{ route('dashboard.audit-logs') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">Full audit log →</a>
    </div>
    @if(isset($recentAudit) && $recentAudit->isNotEmpty())
    <ul class="divide-y divide-slate-100">
        @foreach($recentAudit as $entry)
        <li class="flex items-center gap-4 px-6 py-3">
            <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-slate-100">
                <svg class="h-3.5 w-3.5 text-slate-500" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/>
                </svg>
            </div>
            <div class="flex-1 min-w-0">
                <p class="text-sm text-slate-700 truncate">
                    <span class="font-medium">{{ $entry->staff?->name ?? 'System' }}</span>
                    — <span class="font-mono text-xs bg-slate-100 px-1.5 py-0.5 rounded">{{ $entry->action }}</span>
                </p>
            </div>
            <p class="shrink-0 text-xs text-slate-400">{{ $entry->created_at->diffForHumans() }}</p>
        </li>
        @endforeach
    </ul>
    @else
    <div class="px-6 py-12 text-center">
        <p class="text-sm text-slate-400">No recent activity.</p>
    </div>
    @endif
</div>
