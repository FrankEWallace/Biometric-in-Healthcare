@extends('layouts.dashboard')

@section('title', $patient->full_name)

@section('content')

{{-- Back link + header --}}
<div class="mb-6">
    <a href="{{ route('dashboard.patients') }}" class="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-700 transition mb-4">
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18"/>
        </svg>
        Back to Patients
    </a>

    <div class="flex items-start gap-4">
        <div class="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-blue-100 text-xl font-bold text-blue-700">
            {{ strtoupper(substr($patient->full_name, 0, 1)) }}
        </div>
        <div>
            <h1 class="text-xl font-bold text-slate-900">{{ $patient->full_name }}</h1>
            <div class="mt-1 flex flex-wrap items-center gap-3">
                @if($patient->is_active)
                <span class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-0.5 text-xs font-medium text-emerald-700 border border-emerald-200">
                    <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span> Active
                </span>
                @else
                <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-500">
                    Inactive
                </span>
                @endif

                @if($patient->isEnrolled())
                <span class="inline-flex items-center gap-1 rounded-full bg-violet-50 px-2.5 py-0.5 text-xs font-medium text-violet-700 border border-violet-200">
                    <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/>
                    </svg>
                    Biometrics enrolled
                </span>
                @else
                <span class="inline-flex items-center rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-700 border border-amber-200">
                    No fingerprints enrolled
                </span>
                @endif

                <span class="text-xs text-slate-400">Registered {{ $patient->created_at->format('d M Y') }}</span>
            </div>
        </div>
    </div>
</div>

{{-- Stats row --}}
<div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
    @php
        $miniStats = [
            ['label' => 'Verifications', 'value' => $verificationStats['total']],
            ['label' => 'Successful',    'value' => $verificationStats['matched']],
            ['label' => 'Fingerprints',  'value' => $patient->fingerprints->where('is_active', true)->count()],
            ['label' => 'Success Rate',  'value' => $verificationStats['total'] > 0
                ? round(($verificationStats['matched'] / $verificationStats['total']) * 100) . '%'
                : '—'],
        ];
    @endphp
    @foreach($miniStats as $s)
    <div class="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500 uppercase tracking-wide">{{ $s['label'] }}</p>
        <p class="mt-1.5 text-2xl font-bold text-slate-900">{{ $s['value'] }}</p>
    </div>
    @endforeach
</div>

<div class="grid grid-cols-1 gap-6 lg:grid-cols-2">

    {{-- Patient information --}}
    <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="px-5 py-4 border-b border-slate-100">
            <h2 class="text-sm font-semibold text-slate-800">Patient Information</h2>
        </div>
        <dl class="divide-y divide-slate-100">
            @foreach([
                ['label' => 'Full Name',      'value' => $patient->full_name],
                ['label' => 'Date of Birth',  'value' => $patient->date_of_birth->format('d M Y') . ' (age ' . $patient->date_of_birth->age . ')'],
                ['label' => 'Gender',         'value' => ucfirst($patient->gender ?? '—')],
                ['label' => 'JMBG',           'value' => $patient->jmbg ?? '—', 'mono' => true],
                ['label' => 'Phone',          'value' => $patient->phone ?? '—'],
            ] as $row)
            <div class="flex items-start gap-4 px-5 py-3.5">
                <dt class="w-32 shrink-0 text-xs font-medium text-slate-500 pt-0.5">{{ $row['label'] }}</dt>
                <dd class="flex-1 text-sm {{ ($row['mono'] ?? false) ? 'font-mono' : 'font-normal' }} text-slate-800">
                    {{ $row['value'] }}
                </dd>
            </div>
            @endforeach

            @if($patient->notes)
            <div class="flex items-start gap-4 px-5 py-3.5">
                <dt class="w-32 shrink-0 text-xs font-medium text-slate-500 pt-0.5">Notes</dt>
                <dd class="flex-1 text-sm text-slate-800">{{ $patient->notes }}</dd>
            </div>
            @endif
        </dl>
    </div>

    {{-- Fingerprints --}}
    <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
        <div class="px-5 py-4 border-b border-slate-100">
            <h2 class="text-sm font-semibold text-slate-800">Enrolled Fingerprints</h2>
        </div>

        @php
            $activeFingerprints   = $patient->fingerprints->where('is_active', true);
            $inactiveFingerprints = $patient->fingerprints->where('is_active', false);
        @endphp

        @if($activeFingerprints->isEmpty())
        <div class="px-5 py-12 text-center">
            <svg class="mx-auto h-10 w-10 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33"/>
            </svg>
            <p class="mt-3 text-sm text-slate-500">No fingerprints enrolled yet.</p>
            <p class="text-xs text-slate-400 mt-1">Use the mobile app to enroll fingerprints.</p>
        </div>
        @else
        <ul class="divide-y divide-slate-100">
            @foreach($activeFingerprints as $fp)
            <li class="flex items-center gap-4 px-5 py-3.5">
                <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-violet-100">
                    <svg class="h-5 w-5 text-violet-600" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33"/>
                    </svg>
                </div>
                <div class="flex-1">
                    <p class="text-sm font-medium text-slate-800 capitalize">
                        {{ str_replace('_', ' ', $fp->finger_position) }}
                        @if($fp->is_primary)
                        <span class="ml-1.5 inline-flex items-center rounded-full bg-blue-100 px-1.5 py-0.5 text-xs font-medium text-blue-700">Primary</span>
                        @endif
                    </p>
                    <p class="text-xs text-slate-400">Enrolled {{ $fp->created_at->format('d M Y') }}</p>
                </div>
                <div class="text-right">
                    @php $q = round($fp->quality_score * 100); @endphp
                    <p class="text-xs font-medium {{ $q >= 70 ? 'text-emerald-600' : ($q >= 50 ? 'text-amber-600' : 'text-red-500') }}">
                        {{ $q }}% quality
                    </p>
                </div>
            </li>
            @endforeach
        </ul>
        @endif

        @if($inactiveFingerprints->isNotEmpty())
        <div class="px-5 py-2.5 bg-slate-50 border-t border-slate-100">
            <p class="text-xs text-slate-400">{{ $inactiveFingerprints->count() }} revoked {{ Str::plural('fingerprint', $inactiveFingerprints->count()) }} not shown</p>
        </div>
        @endif
    </div>

</div>

{{-- Recent verification history --}}
<div class="mt-6 rounded-xl border border-slate-200 bg-white shadow-sm">
    <div class="px-5 py-4 border-b border-slate-100">
        <h2 class="text-sm font-semibold text-slate-800">Verification History</h2>
    </div>

    @if($patient->verificationLogs->isEmpty())
    <div class="px-5 py-10 text-center">
        <p class="text-sm text-slate-400">No verification attempts recorded.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead>
                <tr class="bg-slate-50">
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Date & Time</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Operator</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Result</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Score</th>
                    <th class="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Location</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
                @foreach($patient->verificationLogs as $log)
                @php
                    $sc = match($log->status) {
                        'matched'  => ['bg' => 'bg-emerald-50', 'text' => 'text-emerald-700', 'label' => 'Matched',  'border' => 'border-emerald-200'],
                        'no_match' => ['bg' => 'bg-red-50',     'text' => 'text-red-700',     'label' => 'No Match', 'border' => 'border-red-200'],
                        default    => ['bg' => 'bg-amber-50',   'text' => 'text-amber-700',   'label' => 'Error',    'border' => 'border-amber-200'],
                    };
                @endphp
                <tr class="hover:bg-slate-50/60">
                    <td class="px-5 py-3.5">
                        <p class="text-sm text-slate-800">{{ $log->created_at->format('d M Y') }}</p>
                        <p class="text-xs text-slate-400">{{ $log->created_at->format('H:i') }}</p>
                    </td>
                    <td class="px-5 py-3.5 text-sm text-slate-600">{{ $log->operator?->name ?? '—' }}</td>
                    <td class="px-5 py-3.5">
                        <span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium border {{ $sc['bg'] }} {{ $sc['text'] }} {{ $sc['border'] }}">
                            {{ $sc['label'] }}
                        </span>
                    </td>
                    <td class="px-5 py-3.5">
                        <span class="text-sm font-mono text-slate-600">
                            {{ $log->score !== null ? number_format($log->score, 3) : '—' }}
                        </span>
                    </td>
                    <td class="px-5 py-3.5">
                        @if($log->wifi_ssid)
                        <span class="text-xs text-slate-500">{{ $log->wifi_ssid }}</span>
                        @elseif($log->gps_latitude)
                        <span class="text-xs text-slate-500">{{ $log->gps_latitude }}, {{ $log->gps_longitude }}</span>
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

@endsection
