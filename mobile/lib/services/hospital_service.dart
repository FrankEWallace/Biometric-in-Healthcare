import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class HospitalException implements Exception {
  final String message;
  HospitalException(this.message);
}

class HospitalService {
  static const String _baseUrl = AppConfig.baseUrl;

  static const _headers = {'Accept': 'application/json'};

  Map<String, String> _auth(String token) => {
        ..._headers,
        'Authorization': 'Bearer $token',
      };

  Map<String, String> _authJson(String token) => {
        ..._auth(token),
        'Content-Type': 'application/json',
      };

  Future<List<Map<String, dynamic>>> getHospitals({required String token}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/hospitals'),
      headers: _auth(token),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['hospitals'] as List);
    }
    throw HospitalException('Failed to load hospitals.');
  }

  Future<Map<String, dynamic>> createHospital({
    required String token,
    required String name,
    required String code,
    required String city,
    String? wifiSsid,
    double? gpsLatitude,
    double? gpsLongitude,
    int? gpsRadiusMeters,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'code': code,
      'city': city,
      if (wifiSsid != null && wifiSsid.isNotEmpty) 'wifi_ssid': wifiSsid,
      if (gpsLatitude != null)     'gps_latitude': gpsLatitude,
      if (gpsLongitude != null)    'gps_longitude': gpsLongitude,
      if (gpsRadiusMeters != null) 'gps_radius_meters': gpsRadiusMeters,
    };

    final res = await http.post(
      Uri.parse('$_baseUrl/hospitals'),
      headers: _authJson(token),
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 201) {
      return Map<String, dynamic>.from(
          (jsonDecode(res.body) as Map<String, dynamic>)['hospital'] as Map);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as Map<String, dynamic>?;
    if (errors != null) {
      throw HospitalException((errors.values.first as List).first as String);
    }
    throw HospitalException(body['message'] as String? ?? 'Failed to create hospital.');
  }

  Future<Map<String, dynamic>> updateHospital({
    required String token,
    required int hospitalId,
    String? name,
    String? code,
    String? city,
    String? wifiSsid,
    double? gpsLatitude,
    double? gpsLongitude,
    int? gpsRadiusMeters,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{
      if (name != null)            'name': name,
      if (code != null)            'code': code,
      if (city != null)            'city': city,
      if (wifiSsid != null)        'wifi_ssid': wifiSsid,
      if (gpsLatitude != null)     'gps_latitude': gpsLatitude,
      if (gpsLongitude != null)    'gps_longitude': gpsLongitude,
      if (gpsRadiusMeters != null) 'gps_radius_meters': gpsRadiusMeters,
      if (isActive != null)        'is_active': isActive,
    };

    final res = await http.put(
      Uri.parse('$_baseUrl/hospitals/$hospitalId'),
      headers: _authJson(token),
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(
          (jsonDecode(res.body) as Map<String, dynamic>)['hospital'] as Map);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    throw HospitalException(body['message'] as String? ?? 'Failed to update hospital.');
  }

  Future<void> deactivateHospital({
    required String token,
    required int hospitalId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/hospitals/$hospitalId'),
      headers: _auth(token),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw HospitalException(body['message'] as String? ?? 'Failed to deactivate hospital.');
    }
  }
}
