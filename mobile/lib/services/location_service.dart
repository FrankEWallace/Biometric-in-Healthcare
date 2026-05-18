import 'package:geolocator/geolocator.dart';

/// GPS-based geofencing service.
///
/// Configure [hospitalLat], [hospitalLng], and [allowedRadiusMeters] to match
/// the real hospital location before deploying.
class LocationService {
  // ── Hospital anchor point ──────────────────────────────────────────────────
  static const double hospitalLat = 43.8563;   // TODO: replace with real coordinates
  static const double hospitalLng = 18.4131;   // TODO: replace with real coordinates
  static const double allowedRadiusMeters = 200.0;

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
