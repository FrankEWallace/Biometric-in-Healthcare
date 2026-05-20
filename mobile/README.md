# BiH Fingerprint System — Flutter Mobile App

Staff-facing Flutter application for the Mobile-Based Fingerprint Verification System for Patient Identification in Healthcare. Runs on Android and iOS, restricted to hospital premises via GPS geofencing and WiFi SSID enforcement.

---

## Overview

The app is the primary interface for all clinical staff. Nurses register patients and capture fingerprints; the app sends images to the Laravel API, which delegates processing to the Python microservice. Verification scans identify patients at the point of care in real time.

Role-specific dashboards and access controls are enforced both client-side (for UX) and server-side (authoritative).

```
Staff Device  →  Flutter App  →  Laravel API  →  Python Microservice
                                      ↓
                                  MySQL Database
```

---

## Requirements

| Dependency | Version |
|------------|---------|
| Flutter | 3.x (stable channel) |
| Dart | ^3.11.0 |
| Android SDK | API 21+ (Android 5.0+) |
| iOS | 13.0+ |

---

## Setup

```bash
cd mobile

# Fetch dependencies
flutter pub get

# Run on a connected device or emulator
flutter run
```

For physical device testing, the app must reach the Laravel API over the network. Update the base URL in the service layer to the host machine's LAN IP address (not `localhost`).

---

## Configuration

### API Base URL

The base URL is centralised in `lib/config/app_config.dart` and set at build time via `--dart-define`:

```bash
# Development (uses the default 192.168.100.144:8000 if not specified)
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000/api

# Production build
flutter build apk --dart-define=API_BASE_URL=https://api.hospital.tz/api
```

Do not edit service files directly — `AppConfig.baseUrl` is the single source of truth for all six service classes.

### Geofencing

Edit `lib/services/location_service.dart` to set the hospital's GPS anchor and allowed radius:

```dart
static const double hospitalLat = 43.8563;       // replace with real latitude
static const double hospitalLng = 18.4131;        // replace with real longitude
static const double allowedRadiusMeters = 200.0;  // adjust as needed
```

A `DEV BYPASS` is active in the current build (`return true;`) — remove it before production deployment.

### WiFi Restriction

Edit `lib/services/network_service.dart` to list the hospital's WiFi SSID(s):

```dart
static const List<String> allowedSsids = ['Hospital_WiFi'];
```

The WiFi check bypass is controlled by a build flag — not `kDebugMode`:

```bash
flutter run --dart-define=BYPASS_WIFI=true   # dev only
flutter build apk                             # bypass off by default in release
```

Remove `--dart-define=BYPASS_WIFI=true` before any production build.

---

## Dependencies

```yaml
http: ^1.2.2              REST API communication
provider: ^6.1.2          State management
camera: ^0.11.0+2         Fingerprint and face capture
image_picker: ^1.1.2      Gallery fallback for image selection
geolocator: ^13.0.2       GPS position and geofencing
network_info_plus: ^6.0.1 WiFi SSID reading
shared_preferences: ^2.3.4 Persistent local storage (auth token, settings)
```

---

## Directory Structure

```
mobile/lib/
├── main.dart                     App entry point, provider setup, routing
├── config/
│   └── app_config.dart           Centralised build-time config (API base URL, feature flags)
├── models/
│   ├── patient.dart              Patient data model
│   ├── user.dart                 Staff user model
│   └── visit.dart                Visit / appointment model
├── providers/
│   ├── auth_provider.dart        Authentication state (login, token, role)
│   └── theme_provider.dart       Light / dark mode state
├── screens/
│   ├── splash_screen.dart        Initial load and auth check
│   ├── login_screen.dart         Staff login
│   ├── home_dashboard.dart       Role-aware home screen
│   ├── verification_screen.dart  Fingerprint identification scan
│   ├── fingerprint_capture_screen.dart  Camera capture flow
│   ├── fingerprint_preview_screen.dart  Preview before submission
│   ├── patient_registration_screen.dart New patient form
│   ├── camera_screen.dart        Generic camera wrapper
│   ├── ehr_screen.dart           Electronic health record viewer
│   ├── edit_request_screen.dart  Nurse demographic change request form
│   ├── result_screen.dart        Verification result display
│   ├── dashboard/
│   │   ├── nurse_dashboard.dart
│   │   ├── admin_dashboard.dart
│   │   ├── super_admin_dashboard.dart
│   │   └── supervisor_override_screen.dart
│   ├── clerk/
│   │   ├── clerk_dashboard.dart
│   │   ├── clerk_scan_screen.dart
│   │   ├── clerk_summary_screen.dart
│   │   ├── clerk_history_screen.dart
│   │   ├── fingerprint_enroll_screen.dart
│   │   ├── patient_search_screen.dart
│   │   └── visit_detail_screen.dart
│   ├── emergency/
│   │   └── emergency_registration_screen.dart
│   ├── face/
│   │   ├── face_enroll_screen.dart
│   │   └── face_verification_screen.dart
│   ├── visit/
│   │   ├── stage_queue_screen.dart
│   │   └── stage_verify_screen.dart
│   ├── staff/
│   │   ├── staff_screen.dart
│   │   └── staff_form_sheet.dart
│   ├── requests/
│   │   └── requests_screen.dart
│   ├── profile/
│   │   └── profile_screen.dart
│   └── shell/
│       └── app_shell.dart        Bottom navigation shell for authenticated users
├── services/
│   ├── auth_service.dart         Login, logout, token management
│   ├── fingerprint_service.dart  Fingerprint enrollment and verification API calls
│   ├── face_service.dart         Face enrollment and verification API calls
│   ├── patient_service.dart      Patient CRUD and search
│   ├── staff_service.dart        Staff management API calls
│   ├── visit_service.dart        Visit lifecycle API calls
│   ├── location_service.dart     GPS geofencing
│   └── network_service.dart      WiFi SSID restriction
├── theme/
│   └── app_theme.dart            Light and dark Material themes (Inter font)
└── widgets/
    ├── custom_text_field.dart    Labelled input field component
    ├── primary_button.dart       Primary CTA button
    ├── stat_card.dart            Dashboard metric card
    ├── status_snackbar.dart      Success / error feedback bar
    ├── fingerprint_overlay.dart  Camera overlay guide for fingerprint capture
    └── face_overlay.dart         Camera overlay guide for face capture
```

---

## Screens and User Flows

### Login
Staff authenticate with email and password. The returned Sanctum token is stored in `shared_preferences` and attached to every subsequent API request as a Bearer token. The `AuthProvider` exposes the current user's role to all descendants.

### Role-Based Dashboards

| Role | Dashboard | Key Actions |
|------|-----------|-------------|
| `nurse` | `NurseDashboard` | Register patients, capture and enroll fingerprints, run verification scans, submit edit requests |
| `admin` | `AdminDashboard` | Approve edit requests, manage staff, unlock fingerprint records, emergency registration |
| `super_admin` | `SuperAdminDashboard` | Cross-hospital user and hospital management |
| `doctor` | `HomeDashboard` | Read-only patient records, EHR viewer, verification log history |

### Patient Registration
The nurse fills a registration form, then is directed to `FingerprintCaptureScreen` to capture the patient's fingerprint via the device camera. The image is sent to the Laravel `/patients/{id}/enroll` endpoint, which forwards it to the Python service for template extraction. The resulting template is stored in the database — not the raw image.

### Fingerprint Verification
`FingerprintLivenessCameraScreen` streams frames continuously via `startImageStream()`. Once three consecutive frames pass a sharpness quality gate, a six-frame burst is automatically captured and submitted — no manual button press required. The `FingerprintOverlay` widget displays a live quality ring that shifts red → amber → green as the sharpness signal improves. On iOS, the quality calculation reads BGRA8888 luma from the R/G/B channels instead of the YUV420 Y-plane used on Android.

After capture, Laravel calls the Python service to extract a probe template, matches it against all stored templates for the hospital, and returns the identified patient or a no-match result. The result is displayed on `ResultScreen`.

### Face Enrollment and Verification
`FaceEnrollScreen` and `FaceVerificationScreen` follow the same flow using the `/face` endpoints — face detection, embedding extraction, and FAISS similarity search. When the server returns `needs_review`, `FaceVerificationScreen` calls `confirmManualReview()` to create an audit trail entry before navigating, ensuring every manual review decision is logged.

### Visit Lifecycle (Clerk flow)
Clerks search for patients (`PatientSearchScreen`), initiate visits (`ClerkScanScreen`), and progress them through clinical stages (`StageQueueScreen`, `StageVerifyScreen`). Each stage triggers a fingerprint or face verification before the patient advances.

### Edit Requests
Nurses cannot directly modify patient demographics. `EditRequestScreen` submits a change request to the API. Admins review and approve/reject requests through `RequestsScreen`.

### Supervisor Override
`SupervisorOverrideScreen` allows an admin to override a failed or locked verification with a full audit trail entry.

### Emergency Registration
`EmergencyRegistrationScreen` provides a fast-path registration flow for unresponsive or unregistered patients, available to admin and above.

---

## Access Control

### GPS Geofencing
`LocationService.isWithinHospitalRange()` compares the device's GPS coordinates against the configured hospital anchor point and radius (default 200 m). Clinical actions are blocked client-side if the device is outside the perimeter.

### WiFi SSID Restriction
`NetworkService.isConnectedToHospitalWifi()` reads the connected SSID and checks it against the configured allowlist. Actions are blocked if the device is not on the hospital network.

**Important**: Both checks are client-side convenience controls. The Laravel backend performs independent server-side validation. Do not treat client-side gating as a security boundary.

---

## State Management

The app uses the `provider` package with two top-level `ChangeNotifierProvider`s:

| Provider | Responsibility |
|----------|---------------|
| `AuthProvider` | Authenticated user object, Sanctum token, role, login/logout actions |
| `ThemeProvider` | Current theme mode (light/dark), persisted via `shared_preferences` |

Service classes (`AuthService`, `PatientService`, etc.) are plain Dart classes instantiated directly in screens. State that needs to be shared uses `AuthProvider`; everything else is local to the screen.

---

## Theme and Design

- Font family: **Inter** (400 / 500 / 600 / 700 / 800 weights, bundled as assets)
- Design language: Apple Health aesthetic — white surfaces, minimal chrome, clean typography
- Both light and dark themes defined in `app_theme.dart`
- App is locked to portrait orientation at startup

---

## Platform Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is required to capture fingerprint and face images.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location is used to verify you are within the hospital premises.</string>
```

For WiFi SSID reading on iOS, the "Access WiFi Information" entitlement must be enabled in the provisioning profile. Without it, the SSID is unavailable and the service fails open (returns `true`) to avoid blocking real staff — change this policy before production.

---

## Building for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS (requires Xcode and Apple Developer account)
flutter build ios --release
```

Before building for production:
1. Remove the `DEV BYPASS` return in `location_service.dart`.
2. Set the correct hospital GPS coordinates and allowed radius in `LocationService`.
3. Set the correct WiFi SSID(s) in `NetworkService`.
4. Do **not** pass `--dart-define=BYPASS_WIFI=true` to the build command.
5. Pass `--dart-define=API_BASE_URL=https://api.hospital.tz/api` with the production HTTPS domain.

---

## Related Services

- `../laravel/` — Laravel 11 REST API (primary backend)
- `../python-service/` — FastAPI fingerprint and face processing microservice
