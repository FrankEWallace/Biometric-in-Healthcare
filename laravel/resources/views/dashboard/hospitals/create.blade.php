@extends('layouts.dashboard')

@section('title', 'New Hospital')
@section('subtitle', 'Register a new facility in the system.')

@section('content')

<div class="max-w-2xl">

    {{-- ── Back ──────────────────────────────────────────────────────────────── --}}
    <a href="{{ route('dashboard.hospitals.index') }}"
       class="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-800 transition-colors mb-6">
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18"/>
        </svg>
        Back to Hospitals
    </a>

    <form method="POST" action="{{ route('dashboard.hospitals.store') }}" class="space-y-6">
        @csrf

        {{-- ── Basic Info ───────────────────────────────────────────────────── --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Basic Information</h2>
                <p class="mt-0.5 text-xs text-slate-400">Name and location — required to register the hospital.</p>
            </div>
            <div class="px-5 py-5 space-y-4">

                <div>
                    <label for="name" class="block text-sm font-medium text-slate-700 mb-1.5">Hospital Name <span class="text-red-500">*</span></label>
                    <input type="text" id="name" name="name" value="{{ old('name') }}" required
                           class="w-full rounded-lg border {{ $errors->has('name') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('name')
                    <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                    @enderror
                </div>

                <div>
                    <label for="city" class="block text-sm font-medium text-slate-700 mb-1.5">City <span class="text-red-500">*</span></label>
                    <input type="text" id="city" name="city" value="{{ old('city') }}" required
                           class="w-full rounded-lg border {{ $errors->has('city') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('city')
                    <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                    @enderror
                </div>

            </div>
        </div>

        {{-- ── Geofencing ───────────────────────────────────────────────────── --}}
        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Geofencing <span class="ml-2 text-xs font-normal text-slate-400">(optional — can be configured later)</span></h2>
                <p class="mt-0.5 text-xs text-slate-400">WiFi SSID and GPS coordinates restrict mobile app access to hospital premises.</p>
            </div>
            <div class="px-5 py-5 space-y-4">

                <div>
                    <label for="wifi_ssid" class="block text-sm font-medium text-slate-700 mb-1.5">WiFi SSID</label>
                    <input type="text" id="wifi_ssid" name="wifi_ssid" value="{{ old('wifi_ssid') }}"
                           placeholder="e.g. Hospital-Internal"
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('wifi_ssid')
                    <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                    @enderror
                </div>

                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label for="gps_latitude" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Latitude</label>
                        <input type="number" id="gps_latitude" name="gps_latitude" value="{{ old('gps_latitude') }}"
                               step="0.0000001" placeholder="e.g. 43.8476"
                               class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('gps_latitude')
                        <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                        @enderror
                    </div>
                    <div>
                        <label for="gps_longitude" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Longitude</label>
                        <input type="number" id="gps_longitude" name="gps_longitude" value="{{ old('gps_longitude') }}"
                               step="0.0000001" placeholder="e.g. 18.4131"
                               class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800 placeholder:text-slate-400
                                      focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('gps_longitude')
                        <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                        @enderror
                    </div>
                </div>

                <div>
                    <label for="gps_radius_meters" class="block text-sm font-medium text-slate-700 mb-1.5">GPS Radius (metres)</label>
                    <input type="number" id="gps_radius_meters" name="gps_radius_meters" value="{{ old('gps_radius_meters', 200) }}"
                           min="50" max="5000"
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    <p class="mt-1 text-xs text-slate-400">Default 200 m. Minimum 50 m, maximum 5 000 m.</p>
                    @error('gps_radius_meters')
                    <p class="mt-1 text-xs text-red-600">{{ $message }}</p>
                    @enderror
                </div>

            </div>
        </div>

        {{-- ── Actions ──────────────────────────────────────────────────────── --}}
        <div class="flex items-center justify-end gap-3">
            <a href="{{ route('dashboard.hospitals.index') }}"
               class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 shadow-sm hover:bg-slate-50 transition-colors">
                Cancel
            </a>
            <button type="submit"
                    class="rounded-lg bg-blue-600 px-5 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
                Create Hospital
            </button>
        </div>

    </form>
</div>

@endsection
