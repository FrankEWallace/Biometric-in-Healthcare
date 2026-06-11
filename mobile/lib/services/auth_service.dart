import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static const String _baseUrl = AppConfig.baseUrl;
  static const String _prefKeyToken = 'auth_token';
  static const String _prefKeyUser  = 'auth_user';

  String? _token;
  User?   _currentUser;

  String? get token          => _token;
  User?   get currentUser    => _currentUser;
  bool    get isAuthenticated => _token != null;

  /// Restores a previously persisted session. Returns the user if found,
  /// null if no saved session exists.
  Future<User?> restoreSession() async {
    final prefs     = await SharedPreferences.getInstance();
    final token     = prefs.getString(_prefKeyToken);
    final userJson  = prefs.getString(_prefKeyUser);
    if (token == null || userJson == null) return null;

    final userData = jsonDecode(userJson) as Map<String, dynamic>;
    userData['token'] = token;
    _token        = token;
    _currentUser  = User.fromJson(userData);
    return _currentUser;
  }

  /// POST /api/auth/login  →  { user, token }
  Future<User> login(String username, String password) async {
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {
              ...AppConfig.defaultHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AuthException('Could not reach the server. Check your connection.');
    }

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      final userData = body['user'] as Map<String, dynamic>;
      userData['token'] = body['token'] as String;

      final user = User.fromJson(userData);
      _token       = user.token;
      _currentUser = user;
      await _persistSession(user);
      return user;
    }

    final message = body['message'] as String? ??
        body['error']   as String? ??
        'Invalid credentials.';
    throw AuthException(message);
  }

  /// PUT /api/auth/profile  →  { user }
  Future<User> updateProfile({required String name}) async {
    if (_token == null) throw const AuthException('Not authenticated.');

    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('$_baseUrl/auth/profile'),
            headers: authHeaders,
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AuthException('Could not reach the server. Check your connection.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      final userData = body['user'] as Map<String, dynamic>;
      userData['token'] = _token!;
      _currentUser = User.fromJson(userData);
      await _persistSession(_currentUser!);
      return _currentUser!;
    }

    final message = body['message'] as String? ??
        body['error']   as String? ??
        'Update failed.';
    throw AuthException(message);
  }

  /// Clear session from memory and disk
  Future<void> logout() async {
    _token       = null;
    _currentUser = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyToken);
    await prefs.remove(_prefKeyUser);
  }

  Map<String, String> get authHeaders => {
        ...AppConfig.defaultHeaders,
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<void> _persistSession(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final userData = user.toJson()..remove('token');
    await prefs.setString(_prefKeyToken, user.token);
    await prefs.setString(_prefKeyUser,  jsonEncode(userData));
  }
}
