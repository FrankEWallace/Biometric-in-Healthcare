import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS-based geofencing service.
///
/// The preferred gate is [isWithinConfiguredHospitals]: it fetches the hospital
/// list from the API and checks the device against each hospital's own GPS
/// circle via [isWithinAnyHospital]. Only when that list cannot be fetched
/// (API unreachable / empty) does it fall back to the single-anchor
/// [isWithinHospitalRange]. The server-side geofence remains the authoritative
/// gate; this client check is defence-in-depth.
class LocationService {
  // ── Fallback anchor (used only when API hospital list cannot be fetched) ───
  static const double _fallbackLat         = -6.8235;
  static const double _fallbackLng         = 39.2695;
  static const double _fallbackRadiusMeters = 500.0;

  /// Returns the current [Position], or `null` if permission is denied,
  /// services are off, or the fix times out.
  Future<Position?> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Check whether the device is within range of ANY hospital in [hospitals].
  ///
  /// Each entry must have numeric [gps_latitude], [gps_longitude], and
  /// [gps_radius_meters] fields (as returned by GET /api/hospitals).
  /// Returns `true` in debug mode (development bypass).
  Future<bool> isWithinAnyHospital(List<Map<String, dynamic>> hospitals) async {
    if (kDebugMode) return true;

    final position = await getCurrentPosition();
    if (position == null) return false;

    for (final h in hospitals) {
      final lat    = (h['gps_latitude']    as num?)?.toDouble();
      final lng    = (h['gps_longitude']   as num?)?.toDouble();
      final radius = (h['gps_radius_meters'] as num?)?.toDouble() ?? 200.0;

      if (lat == null || lng == null) continue;

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      if (distance <= radius) return true;
    }

    return false;
  }

  /// Preferred gate: fetch the hospital list and check the device against each
  /// hospital's own GPS circle. Falls back to the single-anchor
  /// [isWithinHospitalRange] ONLY when the list cannot be fetched or is empty.
  ///
  /// [fetchHospitals] is injected so [LocationService] stays free of any
  /// http/auth dependency, matching its dependency-free style.
  Future<bool> isWithinConfiguredHospitals({
    required Future<List<Map<String, dynamic>>> Function() fetchHospitals,
  }) async {
    if (kDebugMode) return true;
    List<Map<String, dynamic>> hospitals;
    try {
      hospitals = await fetchHospitals();
    } catch (_) {
      return isWithinHospitalRange(); // API unreachable — legacy fallback
    }
    if (hospitals.isEmpty) return isWithinHospitalRange();
    return isWithinAnyHospital(hospitals);
  }

  /// Legacy single-anchor check — kept as fallback when the hospital list
  /// cannot be fetched from the API (e.g. no network at login time).
  Future<bool> isWithinHospitalRange() async {
    if (kDebugMode) return true;

    final position = await getCurrentPosition();
    if (position == null) return false;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _fallbackLat,
      _fallbackLng,
    );

    return distance <= _fallbackRadiusMeters;
  }

  /// Returns the raw [LocationPermission] status without triggering a request.
  Future<LocationPermission> getPermissionStatus() =>
      Geolocator.checkPermission();
}
