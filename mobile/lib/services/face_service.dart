import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../config/app_config.dart';

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
  final String status;       // "matched" | "needs_review" | "no_match" | "error"
  final double score;        // cosine similarity 0–1
  final int? logId;          // verification_logs.id — needed for confirmManualReview
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? ehr;
  final Map<String, dynamic>? insurance;

  bool get isMatch       => status == 'matched';
  bool get isNeedsReview => status == 'needs_review';
  bool get isError       => status == 'error';
  // Identity resolved nationally, but this facility is not authorized to view
  // the record (plan 005). No patient PII is present in this case.
  bool get isAccessRestricted => status == 'access_restricted';

  String get patientName =>
      (patient?['full_name'] as String?) ?? 'Unknown';

  int get patientId => (patient?['id'] as int?) ?? 0;

  const FaceVerifyResult({
    required this.status,
    required this.score,
    this.logId,
    this.patient,
    this.ehr,
    this.insurance,
  });

  factory FaceVerifyResult.fromJson(Map<String, dynamic> json) => FaceVerifyResult(
        status:    json['status']    as String? ?? 'no_match',
        score:     (json['score'] as num?)?.toDouble() ?? 0.0,
        logId:     json['log_id']    as int?,
        patient:   json['patient']   as Map<String, dynamic>?,
        ehr:       json['ehr']       as Map<String, dynamic>?,
        insurance: json['insurance'] as Map<String, dynamic>?,
      );
}

/// Result of the face-first → fingerprint-confirm decision-matrix flow
/// (`POST /api/verify/multimodal`).
class MultimodalVerifyResult {
  final String status;            // "matched" | "needs_review" | "no_match"
  final double faceScore;         // cosine similarity 0–1 of the top candidate
  final double fingerprintScore;  // minutiae score 0–100 (0 when fp stage skipped/failed)
  final int? logId;               // verification_logs.id — for confirmManualReview
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? ehr;
  final Map<String, dynamic>? insurance;

  bool get isMatch       => status == 'matched';
  bool get isNeedsReview => status == 'needs_review';

  String get patientName => (patient?['full_name'] as String?) ?? 'Unknown';
  int    get patientId   => (patient?['id'] as int?) ?? 0;

  const MultimodalVerifyResult({
    required this.status,
    required this.faceScore,
    required this.fingerprintScore,
    this.logId,
    this.patient,
    this.ehr,
    this.insurance,
  });

  factory MultimodalVerifyResult.fromJson(Map<String, dynamic> json) =>
      MultimodalVerifyResult(
        status:           json['status'] as String? ?? 'no_match',
        faceScore:        (json['face_score'] as num?)?.toDouble() ?? 0.0,
        fingerprintScore: (json['fingerprint_score'] as num?)?.toDouble() ?? 0.0,
        logId:            json['log_id'] as int?,
        patient:          json['patient']   as Map<String, dynamic>?,
        ehr:              json['ehr']       as Map<String, dynamic>?,
        insurance:        json['insurance'] as Map<String, dynamic>?,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class FaceService {
  static const String _baseUrl = AppConfig.baseUrl;

  Map<String, String> _headers(String token) => {
        ...AppConfig.defaultHeaders,
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $token',
      };

  // ── Enroll ────────────────────────────────────────────────────────────────

  Future<FaceEnrollResult> enrollFace(
    File image, {
    required String token,
    required String patientId,
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final base64Image = await _compressedBase64(image);
    final uri = Uri.parse('$_baseUrl/face/enroll');

    final body = <String, dynamic>{'image': base64Image, 'patient_id': int.parse(patientId)};
    if (gpsLatitude  != null) body['gps_latitude']  = gpsLatitude;
    if (gpsLongitude != null) body['gps_longitude'] = gpsLongitude;
    if (wifiSsid     != null) body['wifi_ssid']     = wifiSsid;

    final response = await _post(uri, token, body);
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
    final base64Image = await _compressedBase64(image);
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

  // ── Multimodal verify (face shortlist → fingerprint confirm) ──────────────

  /// POST /api/verify/multimodal
  ///
  /// Sends a live face photo and a fingerprint photo in one request. The
  /// server runs face liveness + FAISS shortlist, then confirms with a 1:few
  /// fingerprint match. Returns one of: matched / needs_review / no_match.
  ///
  /// A longer timeout is used than the single-modality calls because the
  /// server performs two pipelines (face + fingerprint) in sequence.
  Future<MultimodalVerifyResult> verifyMultimodal({
    required File faceImage,
    required File fingerprintImage,
    required String token,
    String hand = 'right',
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final faceB64 = await _compressedBase64(faceImage);
    final fpB64   = await _compressedBase64(fingerprintImage);
    final uri     = Uri.parse('$_baseUrl/verify/multimodal');

    final body = <String, dynamic>{
      'face_image':        faceB64,
      'fingerprint_image': fpB64,
      'hand':              hand,
    };
    if (gpsLatitude  != null) body['gps_latitude']  = gpsLatitude;
    if (gpsLongitude != null) body['gps_longitude'] = gpsLongitude;
    if (wifiSsid     != null) body['wifi_ssid']     = wifiSsid;

    final response = await _post(uri, token, body, timeout: const Duration(seconds: 60));
    final json     = _parseBody(response);

    if (response.statusCode == 200) return MultimodalVerifyResult.fromJson(json);

    final msg = _message(json);
    throw FaceException(msg, statusCode: response.statusCode, kind: _kind(response.statusCode, msg));
  }

  // ── Manual review confirmation ────────────────────────────────────────────

  /// Records a staff manual confirmation of a borderline face match.
  /// Must be called before navigating away on needs_review decisions.
  Future<void> confirmManualReview({
    required String token,
    required int logId,
    required int patientId,
  }) async {
    final uri = Uri.parse('$_baseUrl/face/verify-confirm');
    final response = await _post(uri, token, {
      'log_id':    logId,
      'patient_id': patientId,
    });
    if (response.statusCode != 200) {
      final json = _parseBody(response);
      final msg  = _message(json);
      throw FaceException(msg, statusCode: response.statusCode);
    }
  }

  /// Re-encode a captured image and return it as base64.
  ///
  /// The image is sent inside a JSON body, where base64 inflates the payload
  /// by ~33%; a raw high-res capture can exceed the server's `post_max_size`
  /// and make the dev server drop the connection ("Could not reach the
  /// server"). We downscale the longest edge to <= 1280 px and step JPEG
  /// quality down until the encoded bytes are comfortably small, then base64
  /// the result. Falls back to the raw bytes if decoding fails.
  Future<String> _compressedBase64(File image) async {
    final raw = await image.readAsBytes();

    final decoded = img.decodeImage(raw);
    if (decoded == null) return base64Encode(raw);

    const maxEdge = 1280;
    final resized = (decoded.width > maxEdge || decoded.height > maxEdge)
        ? img.copyResize(
            decoded,
            width:  decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height >  decoded.width  ? maxEdge : null,
          )
        : decoded;

    var quality = 90;
    var jpg = img.encodeJpg(resized, quality: quality);
    while (jpg.length > 1500 * 1024 && quality > 60) {
      quality -= 10;
      jpg = img.encodeJpg(resized, quality: quality);
    }

    return base64Encode(jpg);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<http.Response> _post(
    Uri uri,
    String token,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await http
          .post(uri, headers: _headers(token), body: jsonEncode(body))
          .timeout(timeout);
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
