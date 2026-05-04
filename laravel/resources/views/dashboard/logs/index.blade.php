@extends('layouts.dashboard')

@section('title', 'Verification Logs')

@section('content')

{{-- Page header --}}
<div class="mb-6">
    <h1 class="text-xl font-semibold text-slate-900 leading-none">Verification Logs</h1>
    <p class="mt-1.5 text-sm text-slate-500">All fingerprint scan results for your facility.</p>
</div>

{{-- Summary metric cards --}}
@php
    $matched = \App\Models\VerificationLog::where('hospital_id', Auth::user()->hospital_id)->where('status', 'matched')->count();
    $failed  = \App\Models\VerificationLog::where('hospital_id', Auth::user()->hospital_id)->where('status', 'no_match')->count();
    $errors  = \App\Models\VerificationLog::where('hospital_id', Auth::user()->hospital_id)->where('status', 'error')->count();
    $total   = $matched + $failed + $errors;
    $rate    = $total > 0 ? round(($matched / $total) * 100) : 0;
@endphp
<div class="grid grid-cols-2 gap-4 sm:grid-cols-4 mb-6">

    <div class="flex flex-col rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm px-5 pt-5 pb-4">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">Total Records</p>
        <p class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">{{ number_format($total) }}</p>
    </div>

    <div class="flex flex-col rounded-xl border border-emerald-200 bg-gradient-to-t from-emerald-50/60 to-white shadow-sm px-5 pt-5 pb-4">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-emerald-200 bg-emerald-50 text-emerald-600">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-emerald-600">Matched</p>
        <p class="mt-1 text-3xl font-semibold tabular-nums text-emerald-700 leading-none tracking-tight">{{ number_format($matched) }}</p>
    </div>

    <div class="flex flex-col rounded-xl border border-red-200 bg-gradient-to-t from-red-50/60 to-white shadow-sm px-5 pt-5 pb-4">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-red-200 bg-red-50 text-red-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-red-500">No Match</p>
        <p class="mt-1 text-3xl font-semibold tabular-nums text-red-600 leading-none tracking-tight">{{ number_format($failed) }}</p>
    </div>

    <div class="flex flex-col rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm px-5 pt-5 pb-4">
        <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18L9 11.25l4.306 4.307a11.95 11.95 0 015.814-5.519l2.74-1.22m0 0l-5.94-2.28m5.94 2.28l-2.28 5.941"/>
            </svg>
        </div>
        <p class="mt-2.5 text-sm text-slate-500">Success Rate</p>
        <p class="mt-1 text-3xl font-semibold tabular-nums leading-none tracking-tight
                   {{ $rate >= 80 ? 'text-emerald-600' : ($rate >= 50 ? 'text-amber-600' : 'text-red-500') }}">
            {{ $rate }}%
        </p>
    </div>

</div>

{{-- Filter bar --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm px-5 py-4 mb-4">
    <form method="GET" action="{{ route('dashboard.logs') }}" class="flex flex-wrap items-end gap-3">

        <div>
            <label class="block text-xs font-medium text-slate-500 mb-1.5">Status</label>
            <select name="status"
                    class="rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-700 shadow-sm bg-white
                           outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-500/20 transition">
                <option value="">All statuses</option>
                <option value="matched"  @selected(request('status') === 'matched')>Matched</option>
                <option value="no_match" @selected(request('status') === 'no_match')>No Match</option>
                <option value="error"    @selected(request('status') === 'error')>Error</option>
            </select>
        </div>

        <div>
            <label class="block text-xs font-medium text-slate-500 mb-1.5">From</label>
            <input type="date" name="from" value="{{ request('from') }}"
                   class="rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-700 shadow-sm
                          outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-500/20 transition">
        </div>

        <div>
            <label class="block text-xs font-medium text-slate-500 mb-1.5">To</label>
            <input type="date" name="to" value="{{ request('to') }}"
                   class="rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-700 shadow-sm
                          outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-500/20 transition">
        </div>

        <div class="flex items-center gap-2 pb-px">
            <button type="submit"
                    class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm
                           hover:bg-blue-700 transition-colors">
                Apply
            </button>
            @if(request()->hasAny(['status','from','to']))
            <a href="{{ route('dashboard.logs') }}"
               class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 shadow-sm
                      hover:bg-slate-50 transition-colors">
                Clear
            </a>
            @endif
        </div>

    </form>
</div>

{{-- Table card --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
        <div>
            <h2 class="text-sm font-semibold text-slate-900 leading-none">Scan Results</h2>
            <p class="mt-1 text-xs text-slate-400">{{ number_format($logs->total()) }} records{{ request()->hasAny(['status','from','to']) ? ' — filtered' : '' }}</p>
        </div>
    </div>

    <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead>
                <tr class="border-b border-slate-100 bg-slate-50/60">
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Date / Time</th>
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Patient</th>
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide hidden sm:table-cell">Operator</th>
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Result</th>
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide hidden md:table-cell">Score</th>
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide hidden lg:table-cell">WiFi / GPS</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @forelse($logs as $log)
                @php
                    $sc = match($log->status) {
                        'matched'  => ['bg' => 'bg-emerald-100', 'text' => 'text-emerald-700', 'dot' => 'bg-emerald-500', 'label' => 'Matched'],
                        'no_match' => ['bg' => 'bg-red-100',     'text' => 'text-red-700',     'dot' => 'bg-red-500',     'label' => 'No Match'],
                        default    => ['bg' => 'bg-amber-100',   'text' => 'text-amber-700',   'dot' => 'bg-amber-500',   'label' => 'Error'],
                    };
                    $initial = strtoupper(substr($log->patient?->full_name ?? '?', 0, 1));
                @endphp
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-3.5 whitespace-nowrap">
                        <p class="font-medium text-slate-800">{{ $log->created_at->format('d M Y') }}</p>
                        <p class="text-xs text-slate-400 tabular-nums">{{ $log->created_at->format('H:i:s') }}</p>
                    </td>
                    <td class="px-5 py-3.5">
                        @if($log->patient)
                        <a href="{{ route('dashboard.patients.show', $log->patient_id) }}"
                           class="flex items-center gap-2.5 group">
                            <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full
                                        {{ $log->status === 'matched' ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-600' }}
                                        text-xs font-semibold">
                                {{ $initial }}
                            </div>
                            <span class="font-medium text-blue-600 group-hover:text-blue-700 transition-colors">
                                {{ $log->patient->full_name }}
                            </span>
                        </a>
                        @else
                        <span class="text-slate-400 italic text-xs">Unknown patient</span>
                        @endif
                    </td>
                    <td class="px-5 py-3.5 text-slate-500 hidden sm:table-cell">
                        {{ $log->operator?->name ?? '—' }}
                    </td>
                    <td class="px-5 py-3.5">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium {{ $sc['bg'] }} {{ $sc['text'] }}">
                            <span class="h-1.5 w-1.5 rounded-full {{ $sc['dot'] }}"></span>
                            {{ $sc['label'] }}
                        </span>
                        @if($log->error_message)
                        <p class="mt-1 text-xs text-slate-400 truncate max-w-[160px]" title="{{ $log->error_message }}">
                            {{ Str::limit($log->error_message, 40) }}
                        </p>
                        @endif
                    </td>
                    <td class="px-5 py-3.5 hidden md:table-cell">
                        <span class="font-mono text-xs text-slate-600 tabular-nums">
                            {{ $log->score !== null ? number_format($log->score, 3) : '—' }}
                        </span>
                    </td>
                    <td class="px-5 py-3.5 hidden lg:table-cell">
                        @if($log->wifi_ssid)
                        <div class="flex items-center gap-1.5 text-xs text-slate-500">
                            <svg class="h-3.5 w-3.5 text-slate-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 017.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 011.06 0z"/>
                            </svg>
                            {{ $log->wifi_ssid }}
                        </div>
                        @elseif($log->gps_latitude)
                        <span class="font-mono text-xs text-slate-500 tabular-nums">
                            {{ number_format($log->gps_latitude, 4) }},
                            {{ number_format($log->gps_longitude, 4) }}
                        </span>
                        @else
                        <span class="text-xs text-slate-300">—</span>
                        @endif
                    </td>
                </tr>
                @empty
                <tr>
                    <td colspan="6" class="px-5 py-16 text-center">
                        <div class="flex flex-col items-center">
                            <div class="flex h-10 w-10 items-center justify-center rounded-full border border-slate-200 bg-slate-50">
                                <svg class="h-5 w-5 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                                </svg>
                            </div>
                            <p class="mt-3 text-sm font-medium text-slate-600">No logs found</p>
                            <p class="mt-1 text-xs text-slate-400">Try adjusting your filters.</p>
                        </div>
                    </td>
                </tr>
                @endforelse
            </tbody>
        </table>
    </div>

    @if($logs->hasPages())
    <div class="border-t border-slate-100 px-5 py-3.5">
        {{ $logs->links() }}
    </div>
    @endif
</div>

@endsection
