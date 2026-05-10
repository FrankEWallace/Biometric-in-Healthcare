@extends('layouts.dashboard')

@section('title', $hospital->name)
@section('subtitle', $hospital->city)

@section('content')

{{-- ── Header ────────────────────────────────────────────────────────────────── --}}
<div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
    <div class="flex items-center gap-3">
        <a href="{{ route('dashboard.hospitals.index') }}"
           class="flex h-8 w-8 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500 shadow-sm hover:bg-slate-50 transition-colors">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18"/>
            </svg>
        </a>
        <div>
            <div class="flex items-center gap-2">
                <h1 class="text-xl font-semibold text-slate-900 leading-none">{{ $hospital->name }}</h1>
                @if($hospital->is_active)
                <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                    <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>Active
                </span>
                @else
                <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-500">
                    <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>Inactive
                </span>
                @endif
            </div>
            <p class="mt-1 text-sm text-slate-400">{{ $hospital->city }}</p>
        </div>
    </div>
</div>

{{-- ── Tabs ─────────────────────────────────────────────────────────────────── --}}
@php
    $tabs = [
        ['key' => 'overview', 'label' => 'Overview'],
        ['key' => 'settings', 'label' => 'Settings'],
        ['key' => 'staff',    'label' => 'Staff'],
    ];
@endphp
<div class="mb-6 flex border-b border-slate-200">
    @foreach($tabs as $t)
    <a href="{{ route('dashboard.hospitals.show', [$hospital, 'tab' => $t['key']]) }}"
       class="relative px-4 py-2.5 text-sm font-medium transition-colors
              {{ $tab === $t['key']
                 ? 'text-blue-600 after:absolute after:bottom-0 after:left-0 after:right-0 after:h-0.5 after:bg-blue-600'
                 : 'text-slate-500 hover:text-slate-800' }}">
        {{ $t['label'] }}
        @if($t['key'] === 'staff')
        <span class="ml-1.5 inline-flex items-center rounded-full bg-slate-100 px-1.5 py-0.5 text-xs font-medium text-slate-500">
            {{ $stats['total_staff'] }}
        </span>
        @endif
    </a>
    @endforeach
</div>

{{-- ════════════════════════════════════════════════════════════════════════════ --}}
{{-- TAB: OVERVIEW                                                               --}}
{{-- ════════════════════════════════════════════════════════════════════════════ --}}
@if($tab === 'overview')

@php
    $enrollRate = $stats['total_patients'] > 0 ? round(($stats['enrolled'] / $stats['total_patients']) * 100) : 0;
    $overviewCards = [
        ['label' => 'Total Patients',     'value' => number_format($stats['total_patients']),
         'sub' => number_format($stats['enrolled']) . ' enrolled (' . $enrollRate . '%)',
         'color' => $enrollRate >= 80 ? 'emerald' : ($enrollRate >= 50 ? 'amber' : 'red'),
         'icon' => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z'],
        ['label' => 'Verifications Today','value' => number_format($stats['ver_today']),
         'sub' => number_format($stats['success_today']) . ' matched (' . $stats['match_rate'] . '%)',
         'color' => $stats['match_rate'] >= 80 ? 'emerald' : ($stats['match_rate'] >= 50 ? 'amber' : 'slate'),
         'icon' => 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z'],
        ['label' => 'Active Staff',       'value' => number_format($stats['total_staff']),
         'sub' => 'across all roles',
         'color' => 'slate',
         'icon' => 'M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z'],
        ['label' => 'Pending Edit Requests','value' => number_format($stats['pending_edits']),
         'sub' => $stats['pending_edits'] > 0 ? 'awaiting review' : 'all clear',
         'color' => $stats['pending_edits'] > 0 ? 'amber' : 'emerald',
         'icon' => 'M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125'],
    ];
    $badgeColors = [
        'emerald' => 'bg-emerald-100 text-emerald-700',
        'amber'   => 'bg-amber-100 text-amber-700',
        'red'     => 'bg-red-100 text-red-700',
        'slate'   => 'bg-slate-100 text-slate-600',
    ];
@endphp

<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
    @foreach($overviewCards as $card)
    <div class="flex flex-col rounded-xl border border-slate-200 bg-gradient-to-t from-blue-50/40 to-white shadow-sm">
        <div class="flex items-start justify-between px-5 pt-5 pb-3">
            <div class="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500">
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.75" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="{{ $card['icon'] }}"/>
                </svg>
            </div>
            <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $badgeColors[$card['color']] }}">
                {{ $card['color'] === 'emerald' ? '✓' : ($card['color'] === 'amber' ? '!' : '·') }}
            </span>
        </div>
        <div class="px-5 pb-5">
            <p class="text-xs text-slate-500">{{ $card['label'] }}</p>
            <div class="mt-1 text-3xl font-semibold tabular-nums text-slate-900 leading-none tracking-tight">{{ $card['value'] }}</div>
            <p class="mt-1.5 text-xs text-slate-400">{{ $card['sub'] }}</p>
        </div>
    </div>
    @endforeach
</div>

@if($stats['locked_fps'] > 0)
<div class="mt-4 flex items-center gap-3 rounded-xl border border-red-200 bg-red-50 px-5 py-4">
    <svg class="h-5 w-5 shrink-0 text-red-500" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
    </svg>
    <p class="text-sm text-red-700">
        <span class="font-semibold">{{ $stats['locked_fps'] }}</span>
        locked {{ Str::plural('fingerprint', $stats['locked_fps']) }} require attention.
    </p>
</div>
@endif


{{-- ════════════════════════════════════════════════════════════════════════════ --}}
{{-- TAB: SETTINGS                                                               --}}
{{-- ════════════════════════════════════════════════════════════════════════════ --}}
@elseif($tab === 'settings')

<div class="max-w-2xl space-y-6">

    <form method="POST" action="{{ route('dashboard.hospitals.update', $hospital) }}">
        @csrf
        @method('PUT')

        {{-- Basic Info --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Basic Information</h2>
            </div>
            <div class="px-5 py-5 space-y-4">

                <div>
                    <label for="name" class="block text-sm font-medium text-slate-700 mb-1.5">Hospital Name <span class="text-red-500">*</span></label>
                    <input type="text" id="name" name="name" value="{{ old('name', $hospital->name) }}" required
                           class="w-full rounded-lg border {{ $errors->has('name') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('name')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="city" class="block text-sm font-medium text-slate-700 mb-1.5">City <span class="text-red-500">*</span></label>
                    <input type="text" id="city" name="city" value="{{ old('city', $hospital->city) }}" required
                           class="w-full rounded-lg border {{ $errors->has('city') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('city')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

            </div>
        </div>

        {{-- Geofencing --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Geofencing</h2>
                <p class="mt-0.5 text-xs text-slate-400">Controls where the mobile app can be used.</p>
            </div>
            <div class="px-5 py-5 space-y-4">

                <div>
                    <label for="wifi_ssid" class="block text-sm font-medium text-slate-700 mb-1.5">WiFi SSID</label>
                    <input type="text" id="wifi_ssid" name="wifi_ssid" value="{{ old('wifi_ssid', $hospital->wifi_ssid) }}"
                           placeholder="e.g. Hospital-Internal"
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('wifi_ssid')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label for="gps_latitude" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Latitude</label>
                        <input type="number" id="gps_latitude" name="gps_latitude"
                               value="{{ old('gps_latitude', $hospital->gps_latitude) }}"
                               step="0.0000001"
                               class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('gps_latitude')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                    </div>
                    <div>
                        <label for="gps_longitude" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Longitude</label>
                        <input type="number" id="gps_longitude" name="gps_longitude"
                               value="{{ old('gps_longitude', $hospital->gps_longitude) }}"
                               step="0.0000001"
                               class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('gps_longitude')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                    </div>
                </div>

                <div>
                    <label for="gps_radius_meters" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Radius (metres)</label>
                    <input type="number" id="gps_radius_meters" name="gps_radius_meters"
                           value="{{ old('gps_radius_meters', $hospital->gps_radius_meters) }}"
                           min="50" max="5000"
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('gps_radius_meters')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

            </div>
        </div>

        {{-- Feature Flags --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Feature Flags</h2>
                <p class="mt-0.5 text-xs text-slate-400">Enable or disable optional capabilities for this hospital.</p>
            </div>
            <div class="px-5 py-5">
                <label class="flex items-start gap-3 cursor-pointer">
                    <input type="checkbox" name="face_recognition_enabled" value="1"
                           {{ old('face_recognition_enabled', $hospital->face_recognition_enabled) ? 'checked' : '' }}
                           class="mt-0.5 h-4 w-4 rounded border-slate-300 text-blue-600 focus:ring-blue-500">
                    <span>
                        <span class="block text-sm font-medium text-slate-800">Facial Recognition</span>
                        <span class="block text-xs text-slate-500 mt-0.5">
                            Allows staff to enroll and verify patients using face capture in addition to fingerprint.
                            Only enable if the Python service has face processing available.
                        </span>
                    </span>
                </label>
            </div>
        </div>

        <div class="flex justify-end">
            <button type="submit"
                    class="rounded-lg bg-blue-600 px-5 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
                Save Changes
            </button>
        </div>

    </form>

    {{-- Danger Zone --}}
    <div class="rounded-xl border {{ $hospital->is_active ? 'border-red-200' : 'border-slate-200' }} bg-white shadow-sm">
        <div class="px-5 py-4 border-b {{ $hospital->is_active ? 'border-red-100' : 'border-slate-100' }}">
            <h2 class="text-sm font-semibold {{ $hospital->is_active ? 'text-red-700' : 'text-slate-700' }}">Danger Zone</h2>
        </div>
        <div class="px-5 py-5 flex items-center justify-between gap-4">
            <div>
                @if($hospital->is_active)
                <p class="text-sm font-medium text-slate-800">Deactivate this hospital</p>
                <p class="text-xs text-slate-400 mt-0.5">Staff will lose access. Patient data is preserved.</p>
                @else
                <p class="text-sm font-medium text-slate-800">Reactivate this hospital</p>
                <p class="text-xs text-slate-400 mt-0.5">Restores access for all active staff.</p>
                @endif
            </div>
            @if($hospital->is_active)
            <form method="POST" action="{{ route('dashboard.hospitals.deactivate', $hospital) }}"
                  x-data
                  @submit.prevent="if(confirm('Deactivate {{ addslashes($hospital->name) }}? Staff will lose access immediately.')) $el.submit()">
                @csrf
                @method('DELETE')
                <button type="submit"
                        class="rounded-lg border border-red-200 bg-red-50 px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-100 transition-colors">
                    Deactivate
                </button>
            </form>
            @else
            <form method="POST" action="{{ route('dashboard.hospitals.reactivate', $hospital) }}">
                @csrf
                <button type="submit"
                        class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm font-medium text-emerald-700 hover:bg-emerald-100 transition-colors">
                    Reactivate
                </button>
            </form>
            @endif
        </div>
    </div>

</div>


{{-- ════════════════════════════════════════════════════════════════════════════ --}}
{{-- TAB: STAFF                                                                  --}}
{{-- ════════════════════════════════════════════════════════════════════════════ --}}
@elseif($tab === 'staff')

{{-- Add Staff form (collapsible) --}}
<div x-data="{ open: {{ $errors->has('name') || $errors->has('username') || $errors->has('email') || $errors->has('role') ? 'true' : 'false' }} }"
     class="mb-6">

    <div class="flex items-center justify-between mb-3">
        <h2 class="text-sm font-semibold text-slate-900">Staff Members</h2>
        <button @click="open = !open"
                class="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>
            </svg>
            Add Staff
        </button>
    </div>

    <div x-show="open" x-cloak x-transition
         class="mb-6 rounded-xl border border-blue-200 bg-blue-50/50 shadow-sm">
        <div class="px-5 py-4 border-b border-blue-100">
            <h3 class="text-sm font-semibold text-slate-900">New Staff Member</h3>
            <p class="mt-0.5 text-xs text-slate-500">Will be assigned to {{ $hospital->name }}.</p>
        </div>
        <form method="POST" action="{{ route('dashboard.hospitals.staff.store', $hospital) }}"
              class="px-5 py-5">
            @csrf
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">

                <div>
                    <label for="s_name" class="block text-sm font-medium text-slate-700 mb-1.5">Full Name <span class="text-red-500">*</span></label>
                    <input type="text" id="s_name" name="name" value="{{ old('name') }}" required
                           class="w-full rounded-lg border {{ $errors->has('name') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('name')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="s_username" class="block text-sm font-medium text-slate-700 mb-1.5">Username <span class="text-red-500">*</span></label>
                    <input type="text" id="s_username" name="username" value="{{ old('username') }}" required
                           class="w-full rounded-lg border {{ $errors->has('username') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('username')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="s_email" class="block text-sm font-medium text-slate-700 mb-1.5">Email <span class="text-red-500">*</span></label>
                    <input type="email" id="s_email" name="email" value="{{ old('email') }}" required
                           class="w-full rounded-lg border {{ $errors->has('email') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('email')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="s_role" class="block text-sm font-medium text-slate-700 mb-1.5">Role <span class="text-red-500">*</span></label>
                    <select id="s_role" name="role" required
                            class="w-full rounded-lg border {{ $errors->has('role') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                   px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        <option value="">Select role…</option>
                        <option value="admin"  {{ old('role') === 'admin'  ? 'selected' : '' }}>Admin</option>
                        <option value="doctor" {{ old('role') === 'doctor' ? 'selected' : '' }}>Doctor</option>
                        <option value="nurse"  {{ old('role') === 'nurse'  ? 'selected' : '' }}>Nurse</option>
                    </select>
                    @error('role')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="s_password" class="block text-sm font-medium text-slate-700 mb-1.5">Password <span class="text-red-500">*</span></label>
                    <input type="password" id="s_password" name="password" required minlength="8"
                           class="w-full rounded-lg border {{ $errors->has('password') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('password')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="s_password_confirmation" class="block text-sm font-medium text-slate-700 mb-1.5">Confirm Password <span class="text-red-500">*</span></label>
                    <input type="password" id="s_password_confirmation" name="password_confirmation" required
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                </div>

            </div>
            <div class="mt-5 flex justify-end gap-3">
                <button type="button" @click="open = false"
                        class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 transition-colors">
                    Cancel
                </button>
                <button type="submit"
                        class="rounded-lg bg-blue-600 px-5 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
                    Create Staff Member
                </button>
            </div>
        </form>
    </div>
</div>

{{-- Filters --}}
<form method="GET" action="{{ route('dashboard.hospitals.show', $hospital) }}"
      class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
    <input type="hidden" name="tab" value="staff">
    <div class="relative flex-1">
        <svg class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400"
             fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 15.803 7.5 7.5 0 0015.803 15.803z"/>
        </svg>
        <input type="text" name="search" value="{{ request('search') }}" placeholder="Search staff…"
               class="w-full rounded-lg border border-slate-200 bg-white py-2 pl-9 pr-4 text-sm text-slate-700 placeholder:text-slate-400
                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
    </div>
    <select name="role"
            class="rounded-lg border border-slate-200 bg-white py-2 pl-3 pr-8 text-sm text-slate-700
                   focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
        <option value="">All roles</option>
        <option value="admin"  {{ request('role') === 'admin'  ? 'selected' : '' }}>Admin</option>
        <option value="doctor" {{ request('role') === 'doctor' ? 'selected' : '' }}>Doctor</option>
        <option value="nurse"  {{ request('role') === 'nurse'  ? 'selected' : '' }}>Nurse</option>
    </select>
    <button type="submit"
            class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 shadow-sm hover:bg-slate-50 transition-colors">
        Filter
    </button>
</form>

{{-- Staff table --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
    @if($staff->isEmpty())
    <div class="flex flex-col items-center justify-center px-5 py-14 text-center">
        <p class="text-sm font-medium text-slate-600">No staff members found</p>
        <p class="mt-1 text-xs text-slate-400">Use the "Add Staff" button above to add the first member.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead>
                <tr class="border-b border-slate-100 bg-slate-50/60">
                    <th class="px-5 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Staff Member</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wide">Role</th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-slate-400 uppercase tracking-wide">Status</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wide">Actions</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @foreach($staff as $member)
                @php
                    $roleBadge = match($member->role) {
                        'admin'  => 'bg-amber-100 text-amber-700',
                        'doctor' => 'bg-sky-100 text-sky-700',
                        'nurse'  => 'bg-emerald-100 text-emerald-700',
                        default  => 'bg-slate-100 text-slate-600',
                    };
                @endphp
                <tr class="hover:bg-slate-50/60 transition-colors" x-data="{ editRole: false }">
                    <td class="px-5 py-3.5">
                        <div class="flex items-center gap-3">
                            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-600 text-xs font-semibold text-white">
                                {{ strtoupper(substr($member->name, 0, 1)) }}
                            </div>
                            <div>
                                <p class="font-medium text-slate-800">{{ $member->name }}</p>
                                <p class="text-xs text-slate-400">{{ $member->email }}</p>
                            </div>
                        </div>
                    </td>
                    <td class="px-4 py-3.5">
                        <div x-show="!editRole">
                            <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $roleBadge }}">
                                {{ ucfirst($member->role) }}
                            </span>
                        </div>
                        <div x-show="editRole" x-cloak>
                            <form method="POST"
                                  action="{{ route('dashboard.hospitals.staff.role', [$hospital, $member]) }}"
                                  class="flex items-center gap-2">
                                @csrf
                                @method('PATCH')
                                <select name="role"
                                        class="rounded-lg border border-slate-200 bg-white py-1 pl-2 pr-7 text-xs text-slate-700
                                               focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                                    <option value="admin"  {{ $member->role === 'admin'  ? 'selected' : '' }}>Admin</option>
                                    <option value="doctor" {{ $member->role === 'doctor' ? 'selected' : '' }}>Doctor</option>
                                    <option value="nurse"  {{ $member->role === 'nurse'  ? 'selected' : '' }}>Nurse</option>
                                </select>
                                <button type="submit"
                                        class="rounded-md bg-blue-600 px-2 py-1 text-xs font-medium text-white hover:bg-blue-700 transition-colors">
                                    Save
                                </button>
                                <button type="button" @click="editRole = false"
                                        class="text-xs text-slate-400 hover:text-slate-600">Cancel</button>
                            </form>
                        </div>
                    </td>
                    <td class="px-4 py-3.5 text-center">
                        @if($member->is_active)
                        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                            <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>Active
                        </span>
                        @else
                        <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-500">
                            <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>Inactive
                        </span>
                        @endif
                    </td>
                    <td class="px-4 py-3.5 text-right">
                        <div class="flex items-center justify-end gap-2">
                            <button @click="editRole = !editRole" x-show="!editRole"
                                    class="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-600 shadow-sm
                                           hover:bg-slate-50 transition-colors">
                                Edit Role
                            </button>
                            @if($member->is_active)
                            @if($member->id !== Auth::id())
                            <form method="POST" action="{{ route('dashboard.hospitals.staff.deactivate', [$hospital, $member]) }}">
                                @csrf
                                <button type="submit"
                                        class="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-red-600 shadow-sm
                                               hover:bg-red-50 hover:border-red-200 transition-colors">
                                    Deactivate
                                </button>
                            </form>
                            @endif
                            @else
                            <form method="POST" action="{{ route('dashboard.hospitals.staff.activate', [$hospital, $member]) }}">
                                @csrf
                                <button type="submit"
                                        class="rounded-lg border border-emerald-200 bg-emerald-50 px-2.5 py-1.5 text-xs font-medium text-emerald-700 shadow-sm
                                               hover:bg-emerald-100 transition-colors">
                                    Reactivate
                                </button>
                            </form>
                            @endif
                        </div>
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    @if($staff->hasPages())
    <div class="border-t border-slate-100 px-5 py-3">
        {{ $staff->links() }}
    </div>
    @endif
    @endif
</div>

@endif

@endsection
