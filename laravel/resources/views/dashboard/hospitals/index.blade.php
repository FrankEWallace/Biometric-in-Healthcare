@extends('layouts.dashboard')

@section('title', 'Hospitals')
@section('subtitle', 'Manage registered facilities and their configuration.')

@section('content')

{{-- ── Header ────────────────────────────────────────────────────────────────── --}}
<div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
    <div>
        <h1 class="text-xl font-semibold text-slate-900 leading-none">Hospitals</h1>
        <p class="mt-1.5 text-sm text-slate-500">{{ $hospitals->total() }} registered {{ Str::plural('facility', $hospitals->total()) }}</p>
    </div>
    <a href="{{ route('dashboard.hospitals.create') }}"
       class="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>
        </svg>
        New Hospital
    </a>
</div>

{{-- ── Filters ──────────────────────────────────────────────────────────────── --}}
<form method="GET" class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
    <div class="relative flex-1">
        <svg class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400"
             fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 15.803 7.5 7.5 0 0015.803 15.803z"/>
        </svg>
        <input type="text" name="search" value="{{ request('search') }}" placeholder="Search by name or city…"
               class="w-full rounded-lg border border-slate-200 bg-white py-2 pl-9 pr-4 text-sm text-slate-700 placeholder:text-slate-400
                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
    </div>
    <select name="status"
            class="rounded-lg border border-slate-200 bg-white py-2 pl-3 pr-8 text-sm text-slate-700
                   focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
        <option value="">All statuses</option>
        <option value="active"   {{ request('status') === 'active'   ? 'selected' : '' }}>Active</option>
        <option value="inactive" {{ request('status') === 'inactive' ? 'selected' : '' }}>Inactive</option>
    </select>
    <button type="submit"
            class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 shadow-sm hover:bg-slate-50 transition-colors">
        Filter
    </button>
    @if(request('search') || request('status'))
    <a href="{{ route('dashboard.hospitals.index') }}"
       class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-500 hover:bg-slate-50 transition-colors">
        Clear
    </a>
    @endif
</form>

{{-- ── Table ────────────────────────────────────────────────────────────────── --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    @if($hospitals->isEmpty())
    <div class="flex flex-col items-center justify-center px-5 py-16 text-center">
        <div class="flex h-12 w-12 items-center justify-center rounded-full border border-slate-200 bg-slate-50">
            <svg class="h-6 w-6 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21"/>
            </svg>
        </div>
        <p class="mt-3 text-sm font-medium text-slate-600">No hospitals found</p>
        <p class="mt-1 text-xs text-slate-400">Try adjusting your filters or add a new hospital.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead>
                <tr class="border-b border-slate-100 bg-slate-50/60">
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Hospital</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Patients</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Staff</th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-slate-400 uppercase tracking-wide">Geofence</th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-slate-400 uppercase tracking-wide">Status</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Actions</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @foreach($hospitals as $hospital)
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-3.5">
                        <div class="flex items-center gap-3">
                            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-slate-50
                                        text-xs font-semibold text-slate-600">
                                {{ strtoupper(substr($hospital->name, 0, 1)) }}
                            </div>
                            <div>
                                <p class="font-medium text-slate-800">{{ $hospital->name }}</p>
                                <p class="text-xs text-slate-400">{{ $hospital->city }}</p>
                            </div>
                        </div>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="font-semibold tabular-nums text-slate-800">{{ number_format($hospital->patients_count) }}</span>
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <span class="tabular-nums text-slate-600">{{ number_format($hospital->users_count) }}</span>
                    </td>
                    <td class="px-4 py-3.5 text-center">
                        @if($hospital->gps_latitude && $hospital->wifi_ssid)
                            <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                                GPS + WiFi
                            </span>
                        @elseif($hospital->gps_latitude)
                            <span class="inline-flex items-center rounded-full bg-sky-100 px-2 py-0.5 text-xs font-medium text-sky-700">GPS</span>
                        @elseif($hospital->wifi_ssid)
                            <span class="inline-flex items-center rounded-full bg-sky-100 px-2 py-0.5 text-xs font-medium text-sky-700">WiFi</span>
                        @else
                            <span class="text-xs text-slate-300">None</span>
                        @endif
                    </td>
                    <td class="px-4 py-3.5 text-center">
                        @if($hospital->is_active)
                            <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                                <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
                                Active
                            </span>
                        @else
                            <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-500">
                                <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>
                                Inactive
                            </span>
                        @endif
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <a href="{{ route('dashboard.hospitals.show', $hospital) }}"
                           class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-600 shadow-sm
                                  hover:bg-slate-50 hover:border-slate-300 transition-colors">
                            Manage
                            <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"/>
                            </svg>
                        </a>
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    @if($hospitals->hasPages())
    <div class="border-t border-slate-100 px-5 py-3">
        {{ $hospitals->links() }}
    </div>
    @endif
    @endif
</div>

@endsection
