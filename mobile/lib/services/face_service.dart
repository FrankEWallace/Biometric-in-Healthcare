import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// ── Error kinds ───────────────────────────────────────────────────────────────

enum FaceErrorKind {
  network,
  noFaceDetected,
  qualityTooLow,
  featureDisabled,
  serviceUnavailable,
  unauthorized,
  notFound,
  serverError,
  invalidResponse,
  unknown,
}

// ── Exception ─────────────────────────────────────────────────────────────────

class FaceException implements Exception {
  final String message;
  final int? statusCode;
  final FaceErrorKind kind;

  const FaceException(this.message, {this.statusCode, this.kind = FaceErrorKind.unknown});

  @override
  String toString() => message;
}

// ── Result models ─────────────────────────────────────────────────────────────

class FaceEnrollResult {
  final int faceTemplateId;
  final double qualityScore;
  final String message;

  const FaceEnrollResult({
    required this.faceTemplateId,
    required this.qualityScore,
    required this.message,
  });

  factory FaceEnrollResult.fromJson(Map<String, dynamic> json) => FaceEnrollResult(
        faceTemplateId: json['face_template_id'] as int? ?? 0,
        qualityScore:   (json['quality_score'] as num?)?.toDouble() ?? 0.0,
        message:        json['message'] as String? ?? 'Enrolled successfully.',
      );
}

class FaceVerifyResult {
  final String status;       // "matched" | "needs_review" | "no_match"
  final double score;        // cosine similarity 0–1
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? ehr;
  final Map<String, dynamic>? insurance;

  bool get isMatch       => status == 'matched';
  bool get isNeedsReview => status == 'needs_review';

  String get patientName =>
      (patient?['full_name'] as String?) ?? 'Unknown';

  int get patientId => (patient?['id'] as int?) ?? 0;

  const FaceVerifyResult({
    required this.status,
    required this.score,
    this.patient,
    this.ehr,
    this.insurance,
  });

  factory FaceVerifyResult.fromJson(Map<String, dynamic> json) => FaceVerifyResult(
        status:    json['status']    as String? ?? 'no_match',
        score:     (json['score'] as num?)?.toDouble() ?? 0.0,
        patient:   json['patient']   as Map<String, dynamic>?,
        ehr:       json['ehr']       as Map<String, dynamic>?,
        insurance: json['insurance'] as Map<String, dynamic>?,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class FaceService {
  static const String _baseUrl = 'http://localhost:8000/api';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type':  'application/json',
        'Accept':        'application/json',
      };

  // ── Enroll ────────────────────────────────────────────────────────────────

  Future<FaceEnrollResult> enrollFace(
    File image, {
    required String token,
    required String patientId,
  }) async {
    final base64Image = base64Encode(await image.readAsBytes());
    final uri = Uri.parse('$_baseUrl/face/enroll');

    final response = await _post(uri, token, {'image': base64Image, 'patient_id': int.parse(patientId)});
    final json     = _parseBody(response);

    if (response.statusCode == 201) return FaceEnrollResult.fromJson(json);

    final msg = _message(json);
    throw FaceException(msg, statusCode: response.statusCode, kind: _kind(response.statusCode, msg));
  }

  // ── Verify ────────────────────────────────────────────────────────────────

  Future<FaceVerifyResult> verifyFace(
    File image, {
    required String token,
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final base64Image = base64Encode(await image.readAsBytes());
    final uri = Uri.parse('$_baseUrl/face/verify');

    final body = <String, dynamic>{'image': base64Image};
    if (gpsLatitude  != null) body['gps_latitude']  = gpsLatitude;
    if (gpsLongitude != null) body['gps_longitude'] = gpsLongitude;
    if (wifiSsid     != null) body['wifi_ssid']     = wifiSsid;

    final response = await _post(uri, token, body);
    final json     = _parseBody(response);

    if (response.statusCode == 200) return FaceVerifyResult.fromJson(json);

    final msg = _message(json);
    throw FaceException(msg, statusCode: response.statusCode, kind: _kind(response.statusCode, msg));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<http.Response> _post(Uri uri, String token, Map<String, dynamic> body) async {
    try {
      return await http
          .post(uri, headers: _headers(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const FaceException('Request timed out. Please try again.',
          kind: FaceErrorKind.network);
    } on SocketException {
      throw const FaceException('No internet connection.',
          kind: FaceErrorKind.network);
    } catch (_) {
      throw const FaceException('Could not reach the server.',
          kind: FaceErrorKind.network);
    }
  }

  Map<String, dynamic> _parseBody(http.Response response) {
    if (response.body.isEmpty) {
      throw FaceException('Empty server response (${response.statusCode}).',
          statusCode: response.statusCode,
          kind: FaceErrorKind.invalidResponse);
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw FaceException('Unexpected server response (${response.statusCode}).',
          statusCode: response.statusCode,
          kind: response.statusCode >= 500
              ? FaceErrorKind.serverError
              : FaceErrorKind.invalidResponse);
    }
  }

  String _message(Map<String, dynamic> json) =>
      json['error'] as String? ?? json['message'] as String? ?? 'An unexpected error occurred.';

  FaceErrorKind _kind(int status, String message) {
    if (status == 401) return FaceErrorKind.unauthorized;
    if (status == 403) {
      if (message.toLowerCase().contains('not enabled')) return FaceErrorKind.featureDisabled;
    }
    if (status == 404) return FaceErrorKind.notFound;
    if (status == 503) return FaceErrorKind.serviceUnavailable;
    if (status >= 500) return FaceErrorKind.serverError;
    if (status == 422) {
      final lower = message.toLowerCase();
      if (lower.contains('no face')) return FaceErrorKind.noFaceDetected;
      if (lower.contains('quality'))  return FaceErrorKind.qualityTooLow;
    }
    return FaceErrorKind.unknown;
  }
}
