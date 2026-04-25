@extends('layouts.dashboard')

@section('title', 'Overview')

@section('content')

{{-- Stats grid --}}
<div class="grid grid-cols-2 gap-4 lg:grid-cols-4">

    @php
        $cards = [
            [
                'label'   => 'Total Patients',
                'value'   => number_format($stats['total_patients']),
                'sub'     => number_format($stats['active_patients']) . ' active',
                'color'   => 'blue',
                'icon'    => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
            ],
            [
                'label'   => 'Fingerprints Enrolled',
                'value'   => number_format($stats['enrolled_patients']),
                'sub'     => 'patients with biometrics',
                'color'   => 'violet',
                'icon'    => 'M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33',
            ],
            [
                'label'   => 'Verifications Today',
                'value'   => number_format($stats['verifications_today']),
                'sub'     => number_format($stats['successful_today']) . ' successful',
                'color'   => 'emerald',
                'icon'    => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
            ],
            [
                'label'   => 'Success Rate (30d)',
                'value'   => $stats['success_rate'] . '%',
                'sub'     => number_format($stats['verifications_week']) . ' this week',
                'color'   => 'amber',
                'icon'    => 'M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z',
            ],
        ];

        $colorMap = [
            'blue'   => ['bg' => 'bg-blue-50',   'icon' => 'text-blue-600',   'ring' => 'ring-blue-100'],
            'violet' => ['bg' => 'bg-violet-50',  'icon' => 'text-violet-600',  'ring' => 'ring-violet-100'],
            'emerald'=> ['bg' => 'bg-emerald-50', 'icon' => 'text-emerald-600', 'ring' => 'ring-emerald-100'],
            'amber'  => ['bg' => 'bg-amber-50',   'icon' => 'text-amber-600',   'ring' => 'ring-amber-100'],
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

{{-- Enrollment progress bar --}}
@php
    $enrollRate = $stats['total_patients'] > 0
        ? round(($stats['enrolled_patients'] / $stats['active_patients']) * 100)
        : 0;
@endphp
<div class="mt-4 rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
    <div class="flex items-center justify-between mb-3">
        <p class="text-sm font-semibold text-slate-700">Enrollment Coverage</p>
        <span class="text-sm font-bold text-slate-900">{{ $enrollRate }}%</span>
    </div>
    <div class="h-2.5 w-full rounded-full bg-slate-100">
        <div class="h-2.5 rounded-full bg-gradient-to-r from-blue-500 to-blue-600 transition-all duration-500"
             style="width: {{ min($enrollRate, 100) }}%"></div>
    </div>
    <p class="mt-2 text-xs text-slate-400">
        {{ number_format($stats['enrolled_patients']) }} of {{ number_format($stats['active_patients']) }} active patients have fingerprints enrolled
    </p>
</div>

{{-- Two-column layout --}}
<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">

    {{-- Recent Verifications --}}
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
            <li class="flex items-center gap-4 px-5 py-3.5">
                @php
                    $statusConfig = [
                        'matched'  => ['bg' => 'bg-emerald-100', 'text' => 'text-emerald-700', 'label' => 'Matched'],
                        'no_match' => ['bg' => 'bg-red-100',     'text' => 'text-red-700',     'label' => 'No Match'],
                        'error'    => ['bg' => 'bg-amber-100',   'text' => 'text-amber-700',   'label' => 'Error'],
                    ];
                    $sc = $statusConfig[$log->status] ?? $statusConfig['error'];
                @endphp
                <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full
                            {{ $log->status === 'matched' ? 'bg-emerald-100' : 'bg-red-100' }}">
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
                    <p class="text-xs text-slate-400">by {{ $log->operator?->name ?? '—' }}</p>
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

    {{-- Recently registered patients --}}
    <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
            <h2 class="text-sm font-semibold text-slate-800">New Patients</h2>
            <a href="{{ route('dashboard.patients') }}" class="text-xs font-medium text-blue-600 hover:text-blue-700">View all →</a>
        </div>

        @if($recentPatients->isEmpty())
        <div class="px-5 py-12 text-center">
            <p class="text-sm text-slate-400">No patients registered yet.</p>
        </div>
        @else
        <ul class="divide-y divide-slate-100">
            @foreach($recentPatients as $patient)
            <li class="px-5 py-3.5">
                <a href="{{ route('dashboard.patients.show', $patient) }}" class="flex items-center gap-3 group">
                    <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xs font-semibold text-blue-700">
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

@endsection
