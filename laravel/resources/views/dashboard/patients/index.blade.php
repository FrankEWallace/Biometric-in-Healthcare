@extends('layouts.dashboard')

@section('title', 'Patients')

@section('content')

{{-- Toolbar --}}
<div class="flex flex-col sm:flex-row sm:items-center gap-3 mb-6">
    <form method="GET" action="{{ route('dashboard.patients') }}" class="flex flex-1 flex-col sm:flex-row gap-3">

        {{-- Search --}}
        <div class="relative flex-1 max-w-sm">
            <svg class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"/>
            </svg>
            <input type="text"
                   name="search"
                   value="{{ request('search') }}"
                   placeholder="Search name, JMBG, phone…"
                   class="w-full rounded-lg border border-slate-300 pl-9 pr-3 py-2.5 text-sm text-slate-900 placeholder-slate-400 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition">
        </div>

        {{-- Enrolled filter --}}
        <select name="enrolled"
                onchange="this.form.submit()"
                class="rounded-lg border border-slate-300 px-3 py-2.5 text-sm text-slate-700 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 bg-white">
            <option value="">All patients</option>
            <option value="1" @selected(request('enrolled') === '1')>Enrolled only</option>
            <option value="0" @selected(request('enrolled') === '0')>Not enrolled</option>
        </select>

        {{-- Status filter --}}
        <select name="status"
                onchange="this.form.submit()"
                class="rounded-lg border border-slate-300 px-3 py-2.5 text-sm text-slate-700 shadow-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 bg-white">
            <option value="">Any status</option>
            <option value="active"   @selected(request('status') === 'active')>Active</option>
            <option value="inactive" @selected(request('status') === 'inactive')>Inactive</option>
        </select>

        <button type="submit"
                class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-blue-700 transition shadow-sm">
            Search
        </button>

        @if(request()->hasAny(['search','enrolled','status']))
        <a href="{{ route('dashboard.patients') }}"
           class="rounded-lg border border-slate-300 px-4 py-2.5 text-sm text-slate-600 hover:bg-slate-50 transition">
            Clear
        </a>
        @endif
    </form>
</div>

{{-- Results info --}}
<p class="mb-4 text-sm text-slate-500">
    Showing <span class="font-medium text-slate-700">{{ $patients->firstItem() }}–{{ $patients->lastItem() }}</span>
    of <span class="font-medium text-slate-700">{{ number_format($patients->total()) }}</span> patients
</p>

{{-- Table --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead>
                <tr class="bg-slate-50">
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Patient</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">JMBG</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Gender</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Phone</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Biometrics</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Status</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Registered</th>
                    <th class="px-5 py-3"></th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @forelse($patients as $patient)
                <tr class="hover:bg-slate-50/60 transition-colors">
                    <td class="px-5 py-4">
                        <div class="flex items-center gap-3">
                            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xs font-semibold text-blue-700">
                                {{ strtoupper(substr($patient->full_name, 0, 1)) }}
                            </div>
                            <div>
                                <p class="text-sm font-medium text-slate-900">{{ $patient->full_name }}</p>
                                <p class="text-xs text-slate-400">
                                    DOB: {{ $patient->date_of_birth->format('d M Y') }}
                                    ({{ $patient->date_of_birth->age }}y)
                                </p>
                            </div>
                        </div>
                    </td>
                    <td class="px-5 py-4">
                        <span class="text-sm font-mono text-slate-600">{{ $patient->jmbg ?? '—' }}</span>
                    </td>
                    <td class="px-5 py-4">
                        <span class="text-sm text-slate-600 capitalize">{{ $patient->gender ?? '—' }}</span>
                    </td>
                    <td class="px-5 py-4">
                        <span class="text-sm text-slate-600">{{ $patient->phone ?? '—' }}</span>
                    </td>
                    <td class="px-5 py-4">
                        @php $fpCount = $patient->fingerprints->where('is_active', true)->count(); @endphp
                        @if($fpCount > 0)
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-medium text-emerald-700 border border-emerald-200">
                            <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                            </svg>
                            {{ $fpCount }} {{ Str::plural('finger', $fpCount) }}
                        </span>
                        @else
                        <span class="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-500">
                            Not enrolled
                        </span>
                        @endif
                    </td>
                    <td class="px-5 py-4">
                        @if($patient->is_active)
                        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-medium text-emerald-700 border border-emerald-200">
                            <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span> Active
                        </span>
                        @else
                        <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-500">
                            <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span> Inactive
                        </span>
                        @endif
                    </td>
                    <td class="px-5 py-4">
                        <span class="text-sm text-slate-500">{{ $patient->created_at->format('d M Y') }}</span>
                    </td>
                    <td class="px-5 py-4 text-right">
                        <a href="{{ route('dashboard.patients.show', $patient) }}"
                           class="text-sm font-medium text-blue-600 hover:text-blue-700 transition">
                            View →
                        </a>
                    </td>
                </tr>
                @empty
                <tr>
                    <td colspan="8" class="px-5 py-16 text-center">
                        <svg class="mx-auto h-10 w-10 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                        </svg>
                        <p class="mt-3 text-sm font-medium text-slate-600">No patients found</p>
                        <p class="mt-1 text-xs text-slate-400">Try adjusting your search or filters.</p>
                    </td>
                </tr>
                @endforelse
            </tbody>
        </table>
    </div>

    {{-- Pagination --}}
    @if($patients->hasPages())
    <div class="border-t border-slate-100 px-5 py-3.5">
        {{ $patients->links() }}
    </div>
    @endif
</div>

@endsection
