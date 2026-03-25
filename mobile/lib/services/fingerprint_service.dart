import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class FingerprintException implements Exception {
  final String message;
  final int? statusCode;
  const FingerprintException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class FingerprintUploadResult {
  final int fingerprintId;
  final String message;

  const FingerprintUploadResult({
    required this.fingerprintId,
    required this.message,
  });

  factory FingerprintUploadResult.fromJson(Map<String, dynamic> json) {
    return FingerprintUploadResult(
      fingerprintId: json['fingerprint_id'] as int? ??
          json['id'] as int? ??
          0,
      message: json['message'] as String? ?? 'Upload successful.',
    );
  }
}

class FingerprintService {
  static const String _baseUrl = 'http://localhost:8000/api';

  /// POST /api/fingerprint/upload
  ///
  /// Sends the image as multipart/form-data.
  /// [token]     – Bearer token from AuthService.
  /// [patientId] – Optional patient ID to associate the fingerprint with.
  Future<FingerprintUploadResult> uploadFingerprint(
    File image, {
    required String token,
    String? patientId,
  }) async {
    final uri = Uri.parse('$_baseUrl/fingerprint/upload');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';

    if (patientId != null) {
      request.fields['patient_id'] = patientId;
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'fingerprint', // field name expected by Laravel
        image.path,
        // mime type inferred from path; jpeg is the camera default
      ),
    );

    late http.StreamedResponse streamed;
    try {
      streamed = await request
          .send()
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const FingerprintException(
          'Could not reach the server. Check your connection.');
    }

    final body = await streamed.stream.bytesToString();
    final Map<String, dynamic> json =
        jsonDecode(body) as Map<String, dynamic>;

    if (streamed.statusCode == 200 || streamed.statusCode == 201) {
      return FingerprintUploadResult.fromJson(json);
    }

    final message = json['message'] as String? ??
        json['error'] as String? ??
        'Upload failed (${streamed.statusCode}).';
    throw FingerprintException(message, statusCode: streamed.statusCode);
  }
}
