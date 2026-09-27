import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';

/// WiFi-based access restriction service.
///
/// The allowed SSID is per-hospital, configured by a super admin via the web
/// admin panel (`hospitals.wifi_ssid`) and passed in to [isConnectedToHospitalWifi].
/// This service holds no hardcoded network names.
///
/// To bypass WiFi checking in a specific build (e.g. development):
///   flutter run --dart-define=BYPASS_WIFI=true
/// Never use this in production builds — set it only in local dev launch configs.
class NetworkService {
  // Explicit build-time flag — false in all production builds unless
  // --dart-define=BYPASS_WIFI=true is passed at compile time.
  static const bool _bypassWifi =
      bool.fromEnvironment('BYPASS_WIFI', defaultValue: false);

  final _info = NetworkInfo();

  /// Returns `true` when the device is connected to a WiFi network whose
  /// SSID matches [expectedSsid] (the current hospital's configured
  /// `wifi_ssid`). If [expectedSsid] is null/empty — the hospital has not
  /// configured a restriction — the check passes, matching the backend's
  /// `GeofenceService` semantics.
  ///
  /// **Android**: requires ACCESS_FINE_LOCATION (or ACCESS_COARSE_LOCATION on
  /// API 29+) to read the SSID. The permission is already declared by the
  /// geolocator package; no extra steps needed.
  ///
  /// **iOS**: SSID access requires the "Access WiFi Information" entitlement
  /// and is only available when the app is associated with a network via NEHotspotNetwork
  /// or connected in a specific way. In practice this means SSID may return
  /// null on iOS without a provisioning profile that includes that entitlement.
  /// When null is returned on iOS the method returns `true` to avoid locking
  /// out real hospital staff — change this policy before production if needed.
  Future<bool> isConnectedToHospitalWifi(String? expectedSsid) async {
    if (_bypassWifi) return true;

    // No restriction configured for this hospital.
    if (expectedSsid == null || expectedSsid.isEmpty) return true;

    // Web (Chrome) is a UI-demo target only and a browser can never read the
    // WiFi SSID — and `Platform.isIOS` below is unsupported on web. Fail open
    // so the dashboard's access checks don't hang on web.
    if (kIsWeb) return true;

    String? ssid;
    try {
      ssid = await _info.getWifiName();
    } catch (_) {
      ssid = null;
    }

    // iOS may wrap the SSID in quotes (e.g. "\"Hospital_WiFi\"").
    if (ssid != null) {
      ssid = ssid.replaceAll('"', '').trim();
    }

    // iOS limitation: null SSID is ambiguous — could be no entitlement rather
    // than wrong network. Fail open on iOS so development / TestFlight builds
    // are not permanently blocked.
    if (ssid == null && Platform.isIOS) return true;

    // On Android a null SSID means not connected to WiFi at all.
    if (ssid == null) return false;

    return ssid == expectedSsid;
  }

  /// Returns the raw SSID string (quotes stripped), or `null` if unavailable.
  Future<String?> getCurrentSsid() async {
    try {
      final raw = await _info.getWifiName();
      return raw?.replaceAll('"', '').trim();
    } catch (_) {
      return null;
    }
  }
}
