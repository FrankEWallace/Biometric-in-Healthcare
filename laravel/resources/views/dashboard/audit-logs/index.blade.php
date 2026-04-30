@extends('layouts.dashboard')

@section('title', Auth::user()->isDoctor() ? 'My Activity Log' : 'Audit Logs')
@section('subtitle', Auth::user()->isDoctor()
    ? 'Your personal access and activity history'
    : 'Immutable record of all system actions — PDPA compliant')

@section('content')

{{-- ── Filter bar ───────────────────────────────────────────────────────────── --}}
<form method="GET" class="mb-6 flex flex-wrap gap-3">
    <select name="action"
            class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
        <option value="">All Actions</option>
        <optgroup label="Fingerprint">
            <option value="fingerprint_match"    @selected(request('action') === 'fingerprint_match')>Fingerprint Match</option>
            <option value="fingerprint_no_match" @selected(request('action') === 'fingerprint_no_match')>Fingerprint No Match</option>
            <option value="fingerprint_enroll"   @selected(request('action') === 'fingerprint_enroll')>Fingerprint Enroll</option>
            <option value="fingerprint_lock"     @selected(request('action') === 'fingerprint_lock')>Fingerprint Lock</option>
            <option value="fingerprint_unlock"   @selected(request('action') === 'fingerprint_unlock')>Fingerprint Unlock</option>
            <option value="fingerprint_delete"   @selected(request('action') === 'fingerprint_delete')>Fingerprint Delete</option>
        </optgroup>
        <optgroup label="Patient">
            <option value="patient_create"  @selected(request('action') === 'patient_create')>Patient Created</option>
            <option value="patient_update"  @selected(request('action') === 'patient_update')>Patient Updated</option>
            <option value="patient_delete"  @selected(request('action') === 'patient_delete')>Patient Deleted</option>
            <option value="manual_override" @selected(request('action') === 'manual_override')>Manual Override</option>
        </optgroup>
        <optgroup label="Edit Requests">
            <option value="edit_request_submitted"  @selected(request('action') === 'edit_request_submitted')>Request Submitted</option>
            <option value="edit_request_approved"   @selected(request('action') === 'edit_request_approved')>Request Approved</option>
            <option value="edit_request_rejected"   @selected(request('action') === 'edit_request_rejected')>Request Rejected</option>
            <option value="edit_request_cancelled"  @selected(request('action') === 'edit_request_cancelled')>Request Cancelled</option>
        </optgroup>
        <optgroup label="Auth / Users">
            <option value="login_success"    @selected(request('action') === 'login_success')>Login Success</option>
            <option value="login_failed"     @selected(request('action') === 'login_failed')>Login Failed</option>
            <option value="user_created"     @selected(request('action') === 'user_created')>User Created</option>
            <option value="user_deactivated" @selected(request('action') === 'user_deactivated')>User Deactivated</option>
        </optgroup>
        <optgroup label="Clinical">
            <option value="ehr_access"       @selected(request('action') === 'ehr_access')>EHR Access</option>
            <option value="insurance_check"  @selected(request('action') === 'insurance_check')>Insurance Check</option>
        </optgroup>
    </select>

    <input type="date" name="from" value="{{ request('from') }}"
           class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
    <input type="date" name="to" value="{{ request('to') }}"
           class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">

    <button type="submit"
            class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors">
        Filter
    </button>
    <a href="{{ route('dashboard.audit-logs') }}"
       class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 transition-colors">
        Clear
    </a>
</form>

{{-- ── Log table ────────────────────────────────────────────────────────────── --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">

    @if($logs->isEmpty())
    <div class="px-6 py-16 text-center">
        <svg class="mx-auto h-12 w-12 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round"
                  d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"/>
        </svg>
        <p class="mt-3 text-sm font-medium text-slate-600">No audit log entries</p>
        <p class="mt-1 text-xs text-slate-400">Try adjusting your filters.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead class="bg-slate-50">
                <tr>
                    <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Timestamp</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Action</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Staff</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Details</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 bg-white">
                @foreach($logs as $log)
                @php
                    $actionColor = match(true) {
                        str_contains($log->action, 'match')      => 'bg-emerald-100 text-emerald-700',
                        str_contains($log->action, 'no_match')   => 'bg-red-100 text-red-700',
                        str_contains($log->action, 'lock')       => 'bg-amber-100 text-amber-700',
                        str_contains($log->action, 'login')      => 'bg-blue-100 text-blue-700',
                        str_contains($log->action, 'create')     => 'bg-sky-100 text-sky-700',
                        str_contains($log->action, 'delete')     => 'bg-red-100 text-red-700',
                        str_contains($log->action, 'approved')   => 'bg-emerald-100 text-emerald-700',
                        str_contains($log->action, 'rejected')   => 'bg-red-100 text-red-700',
                        str_contains($log->action, 'ehr')        => 'bg-violet-100 text-violet-700',
                        default                                  => 'bg-slate-100 text-slate-700',
                    };
                @endphp
                <tr class="hover:bg-slate-50 transition-colors">
                    <td class="px-6 py-4 whitespace-nowrap">
                        <p class="text-sm text-slate-700">{{ $log->created_at->format('d M Y') }}</p>
                        <p class="text-xs text-slate-400">{{ $log->created_at->format('H:i:s') }}</p>
                    </td>
                    <td class="px-4 py-4">
                        <span class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium font-mono {{ $actionColor }}">
                            {{ $log->action }}
                        </span>
                    </td>
                    <td class="px-4 py-4">
                        <p class="text-sm text-slate-700">{{ $log->staff?->name ?? '—' }}</p>
                        @if($log->ip_address)
                        <p class="text-xs text-slate-400 font-mono">{{ $log->ip_address }}</p>
                        @endif
                    </td>
                    <td class="px-4 py-4">
                        @if($log->meta)
                        <div class="text-xs text-slate-500 space-y-0.5">
                            @foreach(array_slice($log->meta, 0, 3) as $key => $val)
                            <p>
                                <span class="font-medium text-slate-600">{{ str_replace('_', ' ', $key) }}:</span>
                                {{ is_array($val) ? json_encode($val) : $val }}
                            </p>
                            @endforeach
                            @if(count($log->meta) > 3)
                            <p class="text-slate-400">+{{ count($log->meta) - 3 }} more fields</p>
                            @endif
                        </div>
                        @else
                        <span class="text-xs text-slate-400">—</span>
                        @endif
                    </td>
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    @if($logs->hasPages())
    <div class="border-t border-slate-100 px-6 py-4">
        {{ $logs->withQueryString()->links() }}
    </div>
    @endif
    @endif
</div>

<p class="mt-4 text-xs text-slate-400 text-center">
    Audit logs are immutable and cannot be edited or deleted. Records are retained for compliance under PDPA 2023.
</p>

@endsection
