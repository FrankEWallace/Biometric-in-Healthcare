import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS-based geofencing service.
///
/// Set [hospitalLat], [hospitalLng], and [allowedRadiusMeters] to your demo /
/// deployment venue before going live.  The kDebugMode bypass below keeps
/// development unblocked — remove it before the final demo.
class LocationService {
  // ── Hospital anchor point ──────────────────────────────────────────────────
  // Updated to Dar es Salaam (development location) — replace with real
  // hospital coordinates before deployment.
  static const double hospitalLat         = -6.827;
  static const double hospitalLng         = 39.2675;
  static const double allowedRadiusMeters = 500.0;

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

  /// Returns `true` when the device is within [allowedRadiusMeters] of the
  /// hospital location.
  ///
  /// Returns `false` if:
  ///   - Location permission is denied.
  ///   - Location services are disabled on the device.
  ///   - Any other error occurs while fetching the position.
  Future<bool> isWithinHospitalRange() async {
    // DEBUG BYPASS — remove before final demo / production deployment
    if (kDebugMode) return true;

    final position = await getCurrentPosition();
    if (position == null) return false;

    final distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      hospitalLat,
      hospitalLng,
    );

    return distanceMeters <= allowedRadiusMeters;
  }

  /// Returns the raw [LocationPermission] status without triggering a request.
  Future<LocationPermission> getPermissionStatus() =>
      Geolocator.checkPermission();
}
