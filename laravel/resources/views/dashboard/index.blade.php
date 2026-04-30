@extends('layouts.dashboard')

@section('title', 'Overview')

@section('content')
    @if(Auth::user()->isSuperAdmin())
        @include('dashboard.partials._superadmin')
    @elseif(Auth::user()->isDoctor())
        @include('dashboard.partials._doctor')
    @else
        @include('dashboard.partials._admin')
    @endif
@endsection
