import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

class PatientException implements Exception {
  final String message;
  final Map<String, dynamic>? errors; // validation errors keyed by field
  const PatientException(this.message, {this.errors});
  @override
  String toString() => message;
}

class PatientService {
  static const String _baseUrl = 'http://192.168.100.144:8000/api';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// GET /api/patients?search=...&per_page=10
  ///
  /// Returns up to 10 patients whose name, hospital ID, or NIDA starts with [query].
  Future<List<PatientModel>> searchPatients({
    required String token,
    required String query,
  }) async {
    late http.Response response;

    try {
      final uri = Uri.parse('$_baseUrl/patients').replace(
        queryParameters: {'search': query, 'per_page': '10'},
      );
      response = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data
          .cast<Map<String, dynamic>>()
          .map(PatientModel.fromJson)
          .toList();
    }

    throw PatientException(
        'Failed to search patients (${response.statusCode}).');
  }

  /// POST /api/patients
  ///
  /// Creates a new patient and returns the created [PatientModel].
  /// Throws [PatientException] on validation error, auth failure, or network issue.
  Future<PatientModel> createPatient({
    required String token,
    required String fullName,
    required String dateOfBirth, // format: yyyy-MM-dd
    String? phone,
    String? gender,
    String? nida,
    String? notes,
  }) async {
    late http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/patients'),
            headers: _headers(token),
            // ignore: use_null_aware_elements
            body: jsonEncode({
              'full_name':     fullName,
              'date_of_birth': dateOfBirth,
              if (phone != null && phone.isNotEmpty) 'phone': phone,
              if (gender != null) 'gender': gender,
              if (nida != null && nida.isNotEmpty) 'nida': nida,
              if (notes != null && notes.isNotEmpty) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return PatientModel.fromJson(body['patient'] as Map<String, dynamic>);
    }

    // 422 validation errors — surface field-level messages
    if (response.statusCode == 422) {
      final errors = body['errors'] as Map<String, dynamic>?;
      final firstMessage = errors?.values.first is List
          ? (errors!.values.first as List).first as String
          : body['message'] as String? ?? 'Validation failed.';
      throw PatientException(firstMessage, errors: errors);
    }

    final message = body['message'] as String? ??
        body['error'] as String? ??
        'Failed to create patient (${response.statusCode}).';
    throw PatientException(message);
  }

  /// POST /api/patients/{patientId}/edit-requests
  ///
  /// Nurse submits a demographic change request for admin review.
  /// [field] must be one of: full_name, phone, date_of_birth, gender
  Future<void> submitEditRequest({
    required String token,
    required int patientId,
    required String field,
    required String newValue,
    required String reason,
  }) async {
    late http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/patients/$patientId/edit-requests'),
            headers: _headers(token),
            body: jsonEncode({
              'field_name': field,
              'new_value':  newValue,
              'reason':     reason,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 201) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 422 || response.statusCode == 409) {
      final errors = body['errors'] as Map<String, dynamic>?;
      final msg = body['error'] as String? ??
          (errors?.values.first is List
              ? (errors!.values.first as List).first as String
              : null) ??
          body['message'] as String? ??
          'Request failed.';
      throw PatientException(msg, errors: errors);
    }

    throw PatientException(
        body['error'] as String? ??
        body['message'] as String? ??
        'Failed to submit edit request (${response.statusCode}).');
  }

  /// GET /api/edit-requests
  ///
  /// Admin/super_admin: fetch pending edit requests for review.
  Future<List<Map<String, dynamic>>> getPendingEditRequests({
    required String token,
  }) async {
    late http.Response response;

    try {
      response = await http
          .get(
            Uri.parse('$_baseUrl/edit-requests'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data.cast<Map<String, dynamic>>();
    }

    throw PatientException(
        'Failed to load edit requests (${response.statusCode}).');
  }

  /// POST /api/patients/emergency
  Future<void> registerPatientEmergency({
    required String token,
    required String name,
    required String dob,
    required String gender,
    required String ward,
    required String reason,
    String? nida,
  }) async {
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/patients/emergency'),
            headers: _headers(token),
            body: jsonEncode({
              'full_name':     name,
              'date_of_birth': dob,
              'gender':        gender,
              'ward':          ward,
              'reason':        reason,
              'is_emergency':  true,
              if (nida != null && nida.isNotEmpty) 'nida': nida,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }
    if (response.statusCode == 201) return;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 422) {
      final errors = body['errors'] as Map<String, dynamic>?;
      final msg = errors?.values.first is List
          ? (errors!.values.first as List).first as String
          : body['message'] as String? ?? 'Validation failed.';
      throw PatientException(msg);
    }
    throw PatientException(body['message'] as String? ??
        'Failed to register emergency patient (${response.statusCode}).');
  }

  /// PUT /api/edit-requests/{id}/approve or /reject
  Future<void> reviewEditRequest({
    required String token,
    required int editRequestId,
    required bool approve,
  }) async {
    final action = approve ? 'approve' : 'reject';
    late http.Response response;

    try {
      response = await http
          .put(
            Uri.parse('$_baseUrl/edit-requests/$editRequestId/$action'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PatientException(
          'Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw PatientException(
        body['error'] as String? ??
        body['message'] as String? ??
        'Failed to $action request (${response.statusCode}).');
  }
}
