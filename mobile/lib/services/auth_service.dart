import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  // Base URL — update to match your Laravel server
  static const String _baseUrl = 'http://10.189.130.132:8000/api';

  // In-memory token storage (replace with flutter_secure_storage later)
  String? _token;
  User? _currentUser;

  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;

  /// POST /api/auth/login  →  { user, token }
  Future<User> login(String username, String password) async {
    final Uri url = Uri.parse('$_baseUrl/auth/login');

    late http.Response response;

    try {
      response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AuthException(
          'Could not reach the server. Check your connection.');
    }

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      // Expected shape: { "user": {...}, "token": "..." }
      final userData = body['user'] as Map<String, dynamic>;
      userData['token'] = body['token'] as String;

      final user = User.fromJson(userData);
      _token = user.token;
      _currentUser = user;
      return user;
    }

    // 401 Unauthorized or 422 Validation error
    final message = body['message'] as String? ??
        body['error'] as String? ??
        'Invalid credentials.';
    throw AuthException(message);
  }

  /// Clear session
  void logout() {
    _token = null;
    _currentUser = null;
  }

  /// Returns auth header map for authenticated requests
  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
}
