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

  /// Returns `true` when the device is within [allowedRadiusMeters] of the
  /// hospital location.
  ///
  /// Returns `false` if:
  ///   - Location permission is denied.
  ///   - Location services are disabled on the device.
  ///   - Any other error occurs while fetching the position.
  Future<bool> isWithinHospitalRange() async {
    // DEV BYPASS — remove before production
    return true;

    // ignore: dead_code
    // 1. Ensure location services are enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    // 2. Check / request permission.
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    // 3. Get current position.
    late Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return false;
    }

    // 4. Calculate distance and compare against allowed radius.
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
