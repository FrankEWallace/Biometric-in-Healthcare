import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// ── Error kind ────────────────────────────────────────────────────────────────

/// Semantic category of a [FingerprintException].
///
/// Callers can switch on this to show context-specific guidance without
/// having to parse the human-readable [FingerprintException.message].
enum FingerprintErrorKind {
  /// Device has no internet connection or request timed out.
  network,

  /// Image is too blurry / low Laplacian variance.
  qualityTooLow,

  /// No fingerprint features could be extracted from the image.
  noFeatures,

  /// Python processing service is unavailable (503).
  serviceUnavailable,

  /// Bearer token is missing or expired (401).
  unauthorized,

  /// Patient or enrolled fingerprint not found (404).
  notFound,

  /// Unexpected 5xx server error.
  serverError,

  /// Server returned a response that couldn't be parsed (e.g. HTML error page).
  invalidResponse,

  /// Anything else.
  unknown,
}

// ── Exception ─────────────────────────────────────────────────────────────────

class FingerprintException implements Exception {
  final String message;
  final int? statusCode;
  final FingerprintErrorKind kind;

  const FingerprintException(
    this.message, {
    this.statusCode,
    this.kind = FingerprintErrorKind.unknown,
  });

  @override
  String toString() => message;
}

// ── Result models ─────────────────────────────────────────────────────────────

class FingerprintRegisterResult {
  final int fingerprintId;
  final double qualityScore;
  final int keypointCount;
  final String featureStatus;
  final String message;

  const FingerprintRegisterResult({
    required this.fingerprintId,
    required this.qualityScore,
    required this.keypointCount,
    required this.featureStatus,
    required this.message,
  });

  factory FingerprintRegisterResult.fromJson(Map<String, dynamic> json) {
    return FingerprintRegisterResult(
      fingerprintId: json['fingerprint_id'] as int? ?? 0,
      qualityScore:  (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      keypointCount: json['keypoint_count'] as int? ?? 0,
      featureStatus: json['feature_status'] as String? ?? 'unknown',
      message:       json['message'] as String? ?? 'Registered successfully.',
    );
  }
}

class FingerprintVerifyResult {
  final String verdict;        // "MATCH" | "NO MATCH"
  final double score;          // 0.0–100.0
  final int    probeKeypoints;
  final String featureStatus;
  final String patientName;
  final int    patientId;
  final String matchedFinger;

  const FingerprintVerifyResult({
    required this.verdict,
    required this.score,
    required this.probeKeypoints,
    required this.featureStatus,
    required this.patientName,
    required this.patientId,
    required this.matchedFinger,
  });

  bool get isMatch => verdict == 'MATCH';

  factory FingerprintVerifyResult.fromJson(Map<String, dynamic> json) {
    final patient = json['patient'] as Map<String, dynamic>? ?? {};
    return FingerprintVerifyResult(
      verdict:        json['verdict']         as String? ?? 'NO MATCH',
      score:          (json['score'] as num?)?.toDouble() ?? 0.0,
      probeKeypoints: json['probe_keypoints'] as int?    ?? 0,
      featureStatus:  json['feature_status']  as String? ?? 'unknown',
      patientName:    patient['full_name']    as String? ?? 'Unknown',
      patientId:      patient['id']           as int?    ?? 0,
      matchedFinger:  json['matched_finger']  as String? ?? '',
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class FingerprintService {
  static const String _baseUrl = 'http://localhost:8000/api';

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  // ── Register ──────────────────────────────────────────────────────────────

  /// POST /api/fingerprint/register
  Future<FingerprintRegisterResult> registerFingerprint(
    File image, {
    required String token,
    required String patientId,
    String fingerPosition = 'right_index',
    bool isPrimary = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/fingerprint/register');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(token))
      ..fields['patient_id']      = patientId
      ..fields['finger_position'] = fingerPosition
      ..fields['is_primary']      = isPrimary ? '1' : '0';

    request.files.add(
      await http.MultipartFile.fromPath('fingerprint', image.path),
    );

    final streamed = await _send(request);
    final json     = await _parseJson(streamed);

    if (streamed.statusCode == 201) {
      return FingerprintRegisterResult.fromJson(json);
    }

    final msg = _extractMessage(json);
    throw FingerprintException(
      msg,
      statusCode: streamed.statusCode,
      kind: _kindFromStatus(streamed.statusCode, msg),
    );
  }

  // ── Verify ────────────────────────────────────────────────────────────────

  /// POST /api/fingerprint/verify
  Future<FingerprintVerifyResult> verifyFingerprint(
    File image, {
    required String token,
    required String patientId,
  }) async {
    final uri = Uri.parse('$_baseUrl/fingerprint/verify');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(token))
      ..fields['patient_id'] = patientId;

    request.files.add(
      await http.MultipartFile.fromPath('fingerprint', image.path),
    );

    final streamed = await _send(request);
    final json     = await _parseJson(streamed);

    if (streamed.statusCode == 200) {
      return FingerprintVerifyResult.fromJson(json);
    }

    final msg = _extractMessage(json);
    throw FingerprintException(
      msg,
      statusCode: streamed.statusCode,
      kind: _kindFromStatus(streamed.statusCode, msg),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Send a [MultipartRequest] and return the response.
  /// Distinguishes timeout, no-connection, and other transport errors.
  Future<http.StreamedResponse> _send(http.MultipartRequest request) async {
    try {
      return await request.send().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const FingerprintException(
        'Request timed out. The server is taking too long — please try again.',
        kind: FingerprintErrorKind.network,
      );
    } on SocketException {
      throw const FingerprintException(
        'No internet connection. Check your network and try again.',
        kind: FingerprintErrorKind.network,
      );
    } on HandshakeException {
      throw const FingerprintException(
        'Secure connection failed. Check the server certificate.',
        kind: FingerprintErrorKind.network,
      );
    } catch (_) {
      throw const FingerprintException(
        'Could not reach the server. Check your connection.',
        kind: FingerprintErrorKind.network,
      );
    }
  }

  /// Read and decode the response body as JSON.
  /// Throws [FingerprintException] with [FingerprintErrorKind.invalidResponse]
  /// when the body is empty or not valid JSON (e.g., an HTML gateway error).
  Future<Map<String, dynamic>> _parseJson(
      http.StreamedResponse streamed) async {
    late String body;
    try {
      body = await streamed.stream.bytesToString();
    } catch (_) {
      throw FingerprintException(
        'Failed to read the server response (${streamed.statusCode}).',
        statusCode: streamed.statusCode,
        kind: FingerprintErrorKind.invalidResponse,
      );
    }

    if (body.isEmpty) {
      throw FingerprintException(
        'The server returned an empty response (${streamed.statusCode}).',
        statusCode: streamed.statusCode,
        kind: streamed.statusCode >= 500
            ? FingerprintErrorKind.serverError
            : FingerprintErrorKind.invalidResponse,
      );
    }

    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      // Server returned an HTML error page (e.g., nginx 502/504).
      throw FingerprintException(
        streamed.statusCode >= 500
            ? 'Server error (${streamed.statusCode}). Please try again later.'
            : 'Unexpected response from the server (${streamed.statusCode}).',
        statusCode: streamed.statusCode,
        kind: streamed.statusCode >= 500
            ? FingerprintErrorKind.serverError
            : FingerprintErrorKind.invalidResponse,
      );
    }
  }

  /// Extract the human-readable error string from a JSON body.
  String _extractMessage(Map<String, dynamic> json, [String fallback = '']) {
    return json['error'] as String? ??
        json['message'] as String? ??
        (fallback.isNotEmpty ? fallback : 'An unexpected error occurred.');
  }

  /// Map an HTTP status code + message to a [FingerprintErrorKind].
  FingerprintErrorKind _kindFromStatus(int status, String message) {
    if (status == 401) return FingerprintErrorKind.unauthorized;
    if (status == 404) return FingerprintErrorKind.notFound;
    if (status == 503) return FingerprintErrorKind.serviceUnavailable;
    if (status >= 500) return FingerprintErrorKind.serverError;

    if (status == 422) {
      final lower = message.toLowerCase();
      if (lower.contains('quality')) return FingerprintErrorKind.qualityTooLow;
      if (lower.contains('feature') || lower.contains('fingerprint')) {
        return FingerprintErrorKind.noFeatures;
      }
    }

    return FingerprintErrorKind.unknown;
  }
}
