@extends('layouts.dashboard')

@section('title', 'Staff Management')
@section('subtitle', 'View and manage hospital staff accounts')

@section('content')

{{-- ── Filter bar ───────────────────────────────────────────────────────────── --}}
<form method="GET" class="mb-6 flex flex-wrap gap-3">
    <div class="relative flex-1 min-w-[200px]">
        <svg class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"/>
        </svg>
        <input type="text" name="search" value="{{ request('search') }}" placeholder="Search by name, username, or email…"
               class="w-full rounded-lg border border-slate-200 bg-white pl-9 pr-4 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
    </div>

    <select name="role"
            class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
        <option value="">All Roles</option>
        <option value="nurse"       @selected(request('role') === 'nurse')>Nurse</option>
        <option value="doctor"      @selected(request('role') === 'doctor')>Doctor</option>
        <option value="admin"       @selected(request('role') === 'admin')>Admin</option>
        @if(Auth::user()->isSuperAdmin())
        <option value="super_admin" @selected(request('role') === 'super_admin')>Super Admin</option>
        @endif
    </select>

    @if(Auth::user()->isSuperAdmin() && $hospitals->isNotEmpty())
    <select name="hospital_id"
            class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
        <option value="">All Hospitals</option>
        @foreach($hospitals as $h)
        <option value="{{ $h->id }}" @selected(request('hospital_id') == $h->id)>{{ $h->name }}</option>
        @endforeach
    </select>
    @endif

    <button type="submit"
            class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors">
        Filter
    </button>
    <a href="{{ route('dashboard.users') }}"
       class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 transition-colors">
        Clear
    </a>
</form>

{{-- ── Staff table ──────────────────────────────────────────────────────────── --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">

    @if($users->isEmpty())
    <div class="px-6 py-16 text-center">
        <svg class="mx-auto h-12 w-12 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round"
                  d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z"/>
        </svg>
        <p class="mt-3 text-sm font-medium text-slate-600">No staff found</p>
        <p class="mt-1 text-xs text-slate-400">Try adjusting your filters.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead class="bg-slate-50">
                <tr>
                    <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Staff Member</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Role</th>
                    @if(Auth::user()->isSuperAdmin())
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Hospital</th>
                    @endif
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Status</th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Actions</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 bg-white">
                @foreach($users as $member)
                @php
                    $roleBadge = match($member->role) {
                        'super_admin' => ['bg' => 'bg-rose-100',    'text' => 'text-rose-700',    'label' => 'Super Admin'],
                        'admin'       => ['bg' => 'bg-amber-100',   'text' => 'text-amber-700',   'label' => 'Admin'],
                        'doctor'      => ['bg' => 'bg-sky-100',     'text' => 'text-sky-700',     'label' => 'Doctor'],
                        'nurse'       => ['bg' => 'bg-emerald-100', 'text' => 'text-emerald-700', 'label' => 'Nurse'],
                        default       => ['bg' => 'bg-slate-100',   'text' => 'text-slate-700',   'label' => ucfirst($member->role)],
                    };
                @endphp
                <tr class="{{ ! $member->is_active ? 'opacity-50' : '' }} hover:bg-slate-50 transition-colors">
                    <td class="px-6 py-4">
                        <div class="flex items-center gap-3">
                            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-100 text-sm font-semibold text-blue-700">
                                {{ strtoupper(substr($member->name, 0, 1)) }}
                            </div>
                            <div>
                                <p class="text-sm font-medium text-slate-800">{{ $member->name }}</p>
                                <p class="text-xs text-slate-400">@{{ $member->username }} · {{ $member->email }}</p>
                            </div>
                        </div>
                    </td>
                    <td class="px-4 py-4">
                        <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $roleBadge['bg'] }} {{ $roleBadge['text'] }}">
                            {{ $roleBadge['label'] }}
                        </span>
                    </td>
                    @if(Auth::user()->isSuperAdmin())
                    <td class="px-4 py-4">
                        <p class="text-sm text-slate-600">{{ $member->hospital?->name ?? '—' }}</p>
                    </td>
                    @endif
                    <td class="px-4 py-4">
                        @if($member->is_active)
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                            <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
                            Active
                        </span>
                        @else
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">
                            <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>
                            Inactive
                        </span>
                        @endif
                    </td>
                    <td class="px-4 py-4 text-right">
                        @if($member->id !== Auth::id())
                        @if($member->is_active)
                        <form method="POST" action="{{ route('dashboard.users.deactivate', $member) }}" class="inline">
                            @csrf
                            <button type="submit"
                                    onclick="return confirm('Deactivate {{ addslashes($member->name) }}? They will lose system access immediately.')"
                                    class="rounded-lg border border-red-200 bg-red-50 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-100 transition-colors">
                                Deactivate
                            </button>
                        </form>
                        @else
                        <form method="POST" action="{{ route('dashboard.users.activate', $member) }}" class="inline">
                            @csrf
                            <button type="submit"
                                    class="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-100 transition-colors">
                                Reactivate
                            </button>
                        </form>
                        @endif
                        @else
                        <span class="text-xs text-slate-400">You</span>
                        @endif
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    @if($users->hasPages())
    <div class="border-t border-slate-100 px-6 py-4">
        {{ $users->withQueryString()->links() }}
    </div>
    @endif
    @endif
</div>

{{-- Note: Staff creation is done via mobile app or CLI (php artisan make:super-admin). --}}
<p class="mt-4 text-xs text-slate-400 text-center">
    To create new staff accounts, use the mobile admin panel or contact your system administrator.
    Super admin accounts require the CLI command <code class="font-mono bg-slate-100 px-1.5 py-0.5 rounded">php artisan make:super-admin</code>.
</p>

@endsection
