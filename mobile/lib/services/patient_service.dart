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
  static const String _baseUrl = 'http://192.168.100.132:8000/api';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

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
    String? jmbg,
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
              if (jmbg != null && jmbg.isNotEmpty) 'jmbg': jmbg,
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
}
