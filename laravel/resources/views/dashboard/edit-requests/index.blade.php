@extends('layouts.dashboard')

@section('title', 'Edit Requests')
@section('subtitle', 'Review and approve patient demographic change requests from nurses')

@section('content')

{{-- ── Filter bar ───────────────────────────────────────────────────────────── --}}
<form method="GET" class="mb-6 flex flex-wrap gap-3">
    <select name="status"
            class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500">
        <option value="pending"   @selected($status === 'pending')>Pending</option>
        <option value="approved"  @selected($status === 'approved')>Approved</option>
        <option value="rejected"  @selected($status === 'rejected')>Rejected</option>
        <option value="cancelled" @selected($status === 'cancelled')>Cancelled</option>
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
    <a href="{{ route('dashboard.edit-requests') }}"
       class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 transition-colors">
        Clear
    </a>
</form>

{{-- ── Table ────────────────────────────────────────────────────────────────── --}}
<div class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">

    @if($requests->isEmpty())
    <div class="px-6 py-16 text-center">
        <svg class="mx-auto h-12 w-12 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round"
                  d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10"/>
        </svg>
        <p class="mt-3 text-sm font-medium text-slate-600">No {{ $status }} edit requests</p>
        <p class="mt-1 text-xs text-slate-400">Requests submitted by nurses will appear here.</p>
    </div>
    @else
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-100">
            <thead class="bg-slate-50">
                <tr>
                    <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Patient</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Field</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Change</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Requested By</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Date</th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wide">Status</th>
                    @if($status === 'pending')
                    <th class="px-4 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wide">Actions</th>
                    @endif
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 bg-white">
                @foreach($requests as $req)
                <tr class="hover:bg-slate-50 transition-colors">
                    <td class="px-6 py-4">
                        <a href="{{ route('dashboard.patients.show', $req->patient_id) }}"
                           class="text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline">
                            {{ $req->patient?->full_name ?? '—' }}
                        </a>
                    </td>
                    <td class="px-4 py-4">
                        <span class="inline-flex items-center rounded-md bg-slate-100 px-2 py-1 text-xs font-medium text-slate-700">
                            {{ str_replace('_', ' ', ucfirst($req->field_name)) }}
                        </span>
                    </td>
                    <td class="px-4 py-4 max-w-xs">
                        <div class="flex items-center gap-2 text-xs">
                            <span class="text-slate-500 truncate max-w-[80px]" title="{{ $req->old_value }}">{{ $req->old_value ?? '—' }}</span>
                            <svg class="h-3 w-3 text-slate-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"/>
                            </svg>
                            <span class="font-semibold text-slate-800 truncate max-w-[80px]" title="{{ $req->new_value }}">{{ $req->new_value }}</span>
                        </div>
                        @if($req->reason)
                        <p class="mt-1 text-xs text-slate-400 truncate max-w-[200px]" title="{{ $req->reason }}">
                            "{{ $req->reason }}"
                        </p>
                        @endif
                    </td>
                    <td class="px-4 py-4">
                        <p class="text-sm text-slate-700">{{ $req->requestedBy?->name ?? '—' }}</p>
                    </td>
                    <td class="px-4 py-4">
                        <p class="text-sm text-slate-600">{{ $req->created_at->format('d M Y') }}</p>
                        <p class="text-xs text-slate-400">{{ $req->created_at->format('H:i') }}</p>
                        @if($req->status === 'pending' && $req->expires_at)
                        <p class="text-xs {{ $req->expires_at->isPast() ? 'text-red-500' : 'text-slate-400' }}">
                            Expires {{ $req->expires_at->diffForHumans() }}
                        </p>
                        @endif
                    </td>
                    <td class="px-4 py-4">
                        @php
                            $sc = match($req->status) {
                                'pending'   => ['bg' => 'bg-amber-100',  'text' => 'text-amber-800',  'label' => 'Pending'],
                                'approved'  => ['bg' => 'bg-emerald-100','text' => 'text-emerald-800','label' => 'Approved'],
                                'rejected'  => ['bg' => 'bg-red-100',    'text' => 'text-red-800',    'label' => 'Rejected'],
                                'cancelled' => ['bg' => 'bg-slate-100',  'text' => 'text-slate-600',  'label' => 'Cancelled'],
                                default     => ['bg' => 'bg-slate-100',  'text' => 'text-slate-600',  'label' => ucfirst($req->status)],
                            };
                        @endphp
                        <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium {{ $sc['bg'] }} {{ $sc['text'] }}">
                            {{ $sc['label'] }}
                        </span>
                        @if(in_array($req->status, ['approved', 'rejected']) && $req->reviewedBy)
                        <p class="mt-1 text-xs text-slate-400">by {{ $req->reviewedBy->name }}</p>
                        @endif
                    </td>
                    @if($status === 'pending')
                    <td class="px-4 py-4 text-right">
                        <div class="flex justify-end gap-2">
                            <form method="POST" action="{{ route('dashboard.edit-requests.approve', $req->id) }}">
                                @csrf
                                <button type="submit"
                                        class="rounded-lg bg-emerald-50 border border-emerald-200 px-3 py-1.5 text-xs font-semibold text-emerald-700 hover:bg-emerald-100 transition-colors"
                                        onclick="return confirm('Approve this edit request for {{ addslashes($req->patient?->full_name) }}?')">
                                    Approve
                                </button>
                            </form>
                            <form method="POST" action="{{ route('dashboard.edit-requests.reject', $req->id) }}">
                                @csrf
                                <button type="submit"
                                        class="rounded-lg bg-red-50 border border-red-200 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-100 transition-colors"
                                        onclick="return confirm('Reject this edit request?')">
                                    Reject
                                </button>
                            </form>
                        </div>
                    </td>
                    @endif
                </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    {{-- Pagination --}}
    @if($requests->hasPages())
    <div class="border-t border-slate-100 px-6 py-4">
        {{ $requests->withQueryString()->links() }}
    </div>
    @endif
    @endif
</div>

@endsection
