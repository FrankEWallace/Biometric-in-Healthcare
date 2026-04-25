@extends('layouts.dashboard')

@section('title', 'Verification Logs')

@section('content')

{{-- Filters --}}
<form method="GET" action="{{ route('dashboard.logs') }}" class="flex flex-wrap items-end gap-3 mb-6">

    <div>
        <label class="block text-xs font-medium text-slate-600 mb-1">Status</label>
        <select name="status"
                class="rounded-lg border border-slate-300 px-3 py-2.5 text-sm text-slate-700 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 bg-white">
            <option value="">All</option>
            <option value="matched"  @selected(request('status') === 'matched')>Matched</option>
            <option value="no_match" @selected(request('status') === 'no_match')>No Match</option>
            <option value="error"    @selected(request('status') === 'error')>Error</option>
        </select>
    </div>

    <div>
        <label class="block text-xs font-medium text-slate-600 mb-1">From</label>
        <input type="date" name="from" value="{{ request('from') }}"
               class="rounded-lg border border-slate-300 px-3 py-2.5 text-sm text-slate-700 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20">
    </div>

    <div>
        <label class="block text-xs font-medium text-slate-600 mb-1">To</label>
        <input type="date" name="to" value="{{ request('to') }}"
               class="rounded-lg border border-slate-300 px-3 py-2.5 text-sm text-slate-700 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20">
    </div>

    <button type="submit"
            class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-blue-700 transition shadow-sm">
        Filter
    </button>

    @if(request()->hasAny(['status','from','to']))
    <a href="{{ route('dashboard.logs') }}"
       class="rounded-lg border border-slate-300 px-4 py-2.5 text-sm text-slate-600 hover:bg-slate-50 transition">
        Clear
    </a>
    @endif
</form>

{{-- Summary chips --}}
<div class="flex flex-wrap gap-3 mb-5">
    @php
        $total   = $logs->total();
        $matched = \App\Models\VerificationLog::where('hospital_id', Auth::user()->hospital_id)->where('status', 'matched')->count();
        $failed  = \App\Models\VerificationLog::where('hospital_id', Auth::user()->hospital_id)->where('status', 'no_match')->count();
    @endphp
    <div class="rounded-lg border border-slate-200 bg-white px-4 py-2.5 shadow-sm text-center min-w-[80px]">
        <p class="text-xs text-slate-500">Showing</p>
        <p class="text-lg font-bold text-slate-900">{{ number_format($logs->total()) }}</p>
    </div>
    <div class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-2.5 shadow-sm text-center min-w-[80px]">
        <p class="text-xs text-emerald-600">Total Matched</p>
        <p class="text-lg font-bold text-emerald-700">{{ number_format($matched) }}</p>
    </div>
    <div class="rounded-lg border border-red-200 bg-red-50 px-4 py-2.5 shadow-sm text-center min-w-[80px]">
        <p class="text-xs text-red-500">Total Failed</p>
        <p class="text-lg font-bold text-red-600">{{ number_format($failed) }}</p>
    </div>
</div>

{{-- Table --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead>
                <tr class="bg-slate-50">
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Date / Time</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Patient</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Operator</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Result</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Score</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">WiFi / GPS</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @forelse($logs as $log)
                @php
                    $sc = match($log->status) {
                        'matched'  => ['bg' => 'bg-emerald-50', 'text' => 'text-emerald-700', 'label' => 'Matched',  'border' => 'border-emerald-200'],
                        'no_match' => ['bg' => 'bg-red-50',     'text' => 'text-red-700',     'label' => 'No Match', 'border' => 'border-red-200'],
                        default    => ['bg' => 'bg-amber-50',   'text' => 'text-amber-700',   'label' => 'Error',    'border' => 'border-amber-200'],
                    };
                @endphp
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-3.5">
                        <p class="text-sm text-slate-800">{{ $log->created_at->format('d M Y') }}</p>
                        <p class="text-xs text-slate-400">{{ $log->created_at->format('H:i:s') }}</p>
                    </td>
                    <td class="px-5 py-3.5">
                        @if($log->patient)
                        <a href="{{ route('dashboard.patients.show', $log->patient_id) }}"
                           class="text-sm font-medium text-blue-600 hover:text-blue-700 transition">
                            {{ $log->patient->full_name }}
                        </a>
                        @else
                        <span class="text-sm text-slate-400 italic">Unknown</span>
                        @endif
                    </td>
                    <td class="px-5 py-3.5">
                        <span class="text-sm text-slate-600">{{ $log->operator?->name ?? '—' }}</span>
                    </td>
                    <td class="px-5 py-3.5">
                        <span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium border {{ $sc['bg'] }} {{ $sc['text'] }} {{ $sc['border'] }}">
                            {{ $sc['label'] }}
                        </span>
                        @if($log->error_message)
                        <p class="mt-1 text-xs text-slate-400 truncate max-w-[160px]" title="{{ $log->error_message }}">
                            {{ Str::limit($log->error_message, 40) }}
                        </p>
                        @endif
                    </td>
                    <td class="px-5 py-3.5">
                        <span class="text-sm font-mono text-slate-600">
                            {{ $log->score !== null ? number_format($log->score, 3) : '—' }}
                        </span>
                    </td>
                    <td class="px-5 py-3.5">
                        @if($log->wifi_ssid)
                        <div class="flex items-center gap-1 text-xs text-slate-500">
                            <svg class="h-3.5 w-3.5 text-slate-400" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 017.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 011.06 0z"/>
                            </svg>
                            {{ $log->wifi_ssid }}
                        </div>
                        @elseif($log->gps_latitude)
                        <span class="text-xs font-mono text-slate-500">
                            {{ number_format($log->gps_latitude, 4) }},
                            {{ number_format($log->gps_longitude, 4) }}
                        </span>
                        @else
                        <span class="text-xs text-slate-400">—</span>
                        @endif
                    </td>
                </tr>
                @empty
                <tr>
                    <td colspan="6" class="px-5 py-16 text-center">
                        <svg class="mx-auto h-10 w-10 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                        </svg>
                        <p class="mt-3 text-sm font-medium text-slate-600">No logs found</p>
                        <p class="mt-1 text-xs text-slate-400">Try adjusting your filters.</p>
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
