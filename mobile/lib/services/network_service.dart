import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// WiFi-based access restriction service.
///
/// Only the SSIDs listed in [allowedSsids] are considered hospital networks.
/// Add or remove SSIDs here as the hospital infrastructure changes.
class NetworkService {
  static const List<String> allowedSsids = ['Hospital_WiFi'];

  final _info = NetworkInfo();

  /// Returns `true` when the device is connected to a WiFi network whose
  /// SSID is in [allowedSsids].
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
  Future<bool> isConnectedToHospitalWifi() async {
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

    return allowedSsids.contains(ssid);
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
