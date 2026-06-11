import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StaffException implements Exception {
  final String message;
  StaffException(this.message);
}

class StaffService {
  static const String _baseUrl = AppConfig.baseUrl;

  Map<String, String> _headers(String token) => {
        ...AppConfig.defaultHeaders,
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<Map<String, dynamic>>> getStaff({required String token}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users'),
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['users'] as List);
    }
    throw StaffException('Failed to load staff.');
  }

  Future<Map<String, dynamic>> createStaff({
    required String token,
    required int hospitalId,
    required String name,
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/users'),
      headers: _headers(token),
      body: jsonEncode({
        'hospital_id': hospitalId,
        'name': name,
        'username': username,
        'email': email,
        'password': password,
        'role': role,
      }),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 201) {
      return Map<String, dynamic>.from(
          (jsonDecode(res.body) as Map<String, dynamic>)['user'] as Map);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as Map<String, dynamic>?;
    if (errors != null) {
      final first = (errors.values.first as List).first as String;
      throw StaffException(first);
    }
    throw StaffException(body['message'] as String? ?? 'Failed to create staff.');
  }

  Future<void> updateStaff({
    required String token,
    required int userId,
    required String name,
    required String email,
    required String role,
    String? phone,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'email': email,
      'role': role,
    };
    if (phone != null && phone.trim().isNotEmpty) payload['phone'] = phone.trim();

    final res = await http.put(
      Uri.parse('$_baseUrl/users/$userId'),
      headers: _headers(token),
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final errors = body['errors'] as Map<String, dynamic>?;
      if (errors != null) {
        throw StaffException((errors.values.first as List).first as String);
      }
      throw StaffException(body['message'] as String? ?? 'Failed to update staff.');
    }
  }

  Future<void> setActive({
    required String token,
    required int userId,
    required bool isActive,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/users/$userId'),
      headers: _headers(token),
      body: jsonEncode({'is_active': isActive}),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw StaffException('Failed to update user.');
    }
  }
}
