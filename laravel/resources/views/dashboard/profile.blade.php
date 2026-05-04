@extends('layouts.dashboard')

@section('title', 'My Profile')
@section('subtitle', 'Manage your account details and password.')

@section('content')

<div class="max-w-2xl space-y-6">

    {{-- ── Profile Info ──────────────────────────────────────────────────────── --}}
    <form method="POST" action="{{ route('dashboard.profile.update') }}"
          enctype="multipart/form-data">
        @csrf
        @method('PUT')

        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Profile Information</h2>
                <p class="mt-0.5 text-xs text-slate-400">Update your name, email, username, and photo.</p>
            </div>
            <div class="px-5 py-5 space-y-5">

                {{-- Avatar --}}
                <div class="flex items-center gap-5">
                    <div class="relative">
                        <img id="avatar-preview"
                             src="{{ $user->avatarUrl() }}"
                             alt="{{ $user->name }}"
                             class="h-16 w-16 rounded-full object-cover border-2 border-slate-200">
                        <label for="avatar"
                               class="absolute -bottom-1 -right-1 flex h-6 w-6 cursor-pointer items-center justify-center
                                      rounded-full border-2 border-white bg-blue-600 shadow-sm hover:bg-blue-700 transition-colors">
                            <svg class="h-3 w-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z"/>
                                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zM18.75 10.5h.008v.008h-.008V10.5z"/>
                            </svg>
                        </label>
                    </div>
                    <div>
                        <p class="text-sm font-medium text-slate-700">Profile Photo</p>
                        <p class="text-xs text-slate-400 mt-0.5">JPG, PNG or WebP. Max 2 MB.</p>
                    </div>
                    <input type="file" id="avatar" name="avatar" accept="image/jpg,image/jpeg,image/png,image/webp"
                           class="sr-only"
                           onchange="document.getElementById('avatar-preview').src = URL.createObjectURL(this.files[0])">
                </div>
                @error('avatar')
                <p class="text-xs text-red-600">{{ $message }}</p>
                @enderror

                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">

                    <div class="sm:col-span-2">
                        <label for="name" class="block text-sm font-medium text-slate-700 mb-1.5">Full Name <span class="text-red-500">*</span></label>
                        <input type="text" id="name" name="name" value="{{ old('name', $user->name) }}" required
                               class="w-full rounded-lg border {{ $errors->has('name') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                      px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('name')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                    </div>

                    <div>
                        <label for="username" class="block text-sm font-medium text-slate-700 mb-1.5">Username <span class="text-red-500">*</span></label>
                        <input type="text" id="username" name="username" value="{{ old('username', $user->username) }}" required
                               class="w-full rounded-lg border {{ $errors->has('username') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                      px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('username')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                    </div>

                    <div>
                        <label for="email" class="block text-sm font-medium text-slate-700 mb-1.5">Email <span class="text-red-500">*</span></label>
                        <input type="email" id="email" name="email" value="{{ old('email', $user->email) }}" required
                               class="w-full rounded-lg border {{ $errors->has('email') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                      px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                        @error('email')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                    </div>

                </div>

                <div class="pt-1">
                    <p class="text-xs text-slate-400">
                        Role: <span class="font-medium text-slate-600">{{ ucfirst(str_replace('_', ' ', $user->role)) }}</span>
                        @if($user->hospital)
                        · Hospital: <span class="font-medium text-slate-600">{{ $user->hospital->name }}</span>
                        @endif
                    </p>
                </div>

            </div>
            <div class="flex justify-end px-5 pb-5">
                <button type="submit"
                        class="rounded-lg bg-blue-600 px-5 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
                    Save Profile
                </button>
            </div>
        </div>

    </form>

    {{-- ── Change Password ───────────────────────────────────────────────────── --}}
    <form method="POST" action="{{ route('dashboard.profile.password') }}">
        @csrf
        @method('PUT')

        <div class="rounded-xl border border-slate-200 bg-white shadow-sm">
            <div class="px-5 py-4 border-b border-slate-100">
                <h2 class="text-sm font-semibold text-slate-900">Change Password</h2>
                <p class="mt-0.5 text-xs text-slate-400">Use a strong password of at least 8 characters.</p>
            </div>
            <div class="px-5 py-5 space-y-4">

                <div>
                    <label for="current_password" class="block text-sm font-medium text-slate-700 mb-1.5">Current Password <span class="text-red-500">*</span></label>
                    <input type="password" id="current_password" name="current_password" required
                           class="w-full rounded-lg border {{ $errors->has('current_password') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('current_password')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="password" class="block text-sm font-medium text-slate-700 mb-1.5">New Password <span class="text-red-500">*</span></label>
                    <input type="password" id="password" name="password" required minlength="8"
                           class="w-full rounded-lg border {{ $errors->has('password') ? 'border-red-400 bg-red-50' : 'border-slate-200 bg-white' }}
                                  px-3 py-2 text-sm text-slate-800 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                    @error('password')<p class="mt-1 text-xs text-red-600">{{ $message }}</p>@enderror
                </div>

                <div>
                    <label for="password_confirmation" class="block text-sm font-medium text-slate-700 mb-1.5">Confirm New Password <span class="text-red-500">*</span></label>
                    <input type="password" id="password_confirmation" name="password_confirmation" required
                           class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-800
                                  focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-100">
                </div>

            </div>
            <div class="flex justify-end px-5 pb-5">
                <button type="submit"
                        class="rounded-lg bg-blue-600 px-5 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 transition-colors">
                    Change Password
                </button>
            </div>
        </div>

    </form>

</div>

@endsection
