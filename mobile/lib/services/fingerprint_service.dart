import '../config/app_config.dart';
import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

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

class FingerprintLivenessResult {
  final bool isLive;
  final double meanDisplacement;
  final int frameCount;
  final String reason;

  /// Single-use server token proving this session passed liveness.
  /// Present only when [isLive] is true; required by enroll-gallery.
  final String? livenessToken;

  const FingerprintLivenessResult({
    required this.isLive,
    required this.meanDisplacement,
    required this.frameCount,
    required this.reason,
    this.livenessToken,
  });

  factory FingerprintLivenessResult.fromJson(Map<String, dynamic> json) {
    return FingerprintLivenessResult(
      isLive:          json['is_live']           as bool?   ?? false,
      meanDisplacement:(json['mean_displacement'] as num?)?.toDouble() ?? 0.0,
      frameCount:      json['frame_count']        as int?    ?? 0,
      reason:          json['reason']             as String? ?? 'unknown',
      livenessToken:   json['liveness_token']     as String?,
    );
  }
}

class HandFingerInfo {
  final int fingerprintId;
  final String fingerPosition;
  final double qualityScore;
  final bool isPrimary;

  const HandFingerInfo({
    required this.fingerprintId,
    required this.fingerPosition,
    required this.qualityScore,
    required this.isPrimary,
  });

  factory HandFingerInfo.fromJson(Map<String, dynamic> json) {
    return HandFingerInfo(
      fingerprintId:  json['fingerprint_id']  as int?    ?? 0,
      fingerPosition: json['finger_position'] as String? ?? '',
      qualityScore:   (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      isPrimary:      json['is_primary']      as bool?   ?? false,
    );
  }
}

class HandEnrollResult {
  final String message;
  final String hand;
  final String? matcher;
  final List<HandFingerInfo> fingers;

  const HandEnrollResult({
    required this.message,
    required this.hand,
    required this.matcher,
    required this.fingers,
  });

  /// True when fewer than 4 fingers landed — worth a retake later.
  bool get isPartial => fingers.length < 4;

  factory HandEnrollResult.fromJson(Map<String, dynamic> json) {
    return HandEnrollResult(
      message: json['message'] as String? ?? 'Hand enrolled.',
      hand:    json['hand']    as String? ?? 'right',
      matcher: json['matcher'] as String?,
      fingers: (json['fingers'] as List<dynamic>? ?? [])
          .map((f) => HandFingerInfo.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HandVerifyResult {
  final String status; // matched | no_match | needs_review
  final double score;  // fused 0.0–100.0
  final String matcher;
  final Map<String, double> perFinger;
  final int? candidatePatientId; // advisory when needs_review
  final Map<String, dynamic>? patient;
  final int? logId;
  final String? note;

  const HandVerifyResult({
    required this.status,
    required this.score,
    required this.matcher,
    required this.perFinger,
    this.candidatePatientId,
    this.patient,
    this.logId,
    this.note,
  });

  bool get isMatch       => status == 'matched';
  bool get isNeedsReview => status == 'needs_review';
  // Identity was resolved nationally, but this facility is not authorized to
  // view the record (plan 005). The server sends no patient PII in this case.
  bool get isAccessRestricted => status == 'access_restricted';

  factory HandVerifyResult.fromJson(Map<String, dynamic> json) {
    final perFingerRaw = json['per_finger'] as Map<String, dynamic>? ?? {};
    return HandVerifyResult(
      status:  json['status']  as String? ?? 'no_match',
      score:   (json['score'] as num?)?.toDouble() ?? 0.0,
      matcher: json['matcher'] as String? ?? 'unknown',
      perFinger: perFingerRaw.map(
          (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0)),
      candidatePatientId: json['candidate_patient_id'] as int?,
      patient: json['patient'] as Map<String, dynamic>?,
      logId:   json['log_id']  as int?,
      note:    json['note']    as String?,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class FingerprintService {
  static const String _baseUrl = AppConfig.baseUrl;

  Map<String, String> _authHeaders(String token) => {
        ...AppConfig.defaultHeaders,
        'Authorization': 'Bearer $token',
      };

  // ── Four-finger ("hand slap") enroll + verify ─────────────────────────────

  /// POST /api/patients/{patientId}/enroll-hand
  ///
  /// Uploads one photo of the whole hand; the server segments it into 4
  /// finger crops, extracts a template per finger, quality-gates them, and
  /// stores one fingerprint row per usable finger (contactless domain).
  Future<HandEnrollResult> enrollHand(
    File image, {
    required String token,
    required String patientId,
    String hand = 'right',
    bool isPrimary = false,
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final response = await _postJson(
      Uri.parse('$_baseUrl/patients/$patientId/enroll-hand'),
      token: token,
      body: {
        'image':      base64Encode(await _compressedJpegBytes(image)),
        'hand':       hand,
        'is_primary': isPrimary,
        if (gpsLatitude  != null) 'gps_latitude':  gpsLatitude,
        if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
        if (wifiSsid     != null) 'wifi_ssid':     wifiSsid,
      },
    );

    final json = _decodeJson(response);
    if (response.statusCode == 201) {
      return HandEnrollResult.fromJson(json);
    }

    final msg = _extractMessage(json);
    throw FingerprintException(
      msg,
      statusCode: response.statusCode,
      kind: _kindFromStatus(response.statusCode, msg),
    );
  }

  /// POST /api/verify/hand
  ///
  /// 1:N identification from one photo of the whole hand: the server
  /// segments 4 probe fingers, fuse-matches them against every enrolled
  /// hand in the hospital, and returns matched / no_match / needs_review.
  Future<HandVerifyResult> verifyHand(
    File image, {
    required String token,
    String hand = 'right',
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final response = await _postJson(
      Uri.parse('$_baseUrl/verify/hand'),
      token: token,
      body: {
        'image': base64Encode(await _compressedJpegBytes(image)),
        'hand':  hand,
        if (gpsLatitude  != null) 'gps_latitude':  gpsLatitude,
        if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
        if (wifiSsid     != null) 'wifi_ssid':     wifiSsid,
      },
    );

    final json = _decodeJson(response);
    if (response.statusCode == 200) {
      return HandVerifyResult.fromJson(json);
    }

    final msg = _extractMessage(json);
    throw FingerprintException(
      msg,
      statusCode: response.statusCode,
      kind: _kindFromStatus(response.statusCode, msg),
    );
  }

  // ── Liveness check ────────────────────────────────────────────────────────

  /// POST /api/fingerprint/liveness-check
  ///
  /// Encodes [frames] as base64 and sends them to the server-side optical-flow
  /// liveness endpoint.  [frames] must contain at least 2 images ordered
  /// oldest → newest (same order they were captured).
  Future<FingerprintLivenessResult> checkLiveness(
    List<XFile> frames, {
    required String token,
  }) async {
    if (frames.length < 2) {
      throw const FingerprintException(
        'At least 2 frames are required for liveness check.',
        kind: FingerprintErrorKind.unknown,
      );
    }

    final base64Frames = await Future.wait(
      frames.map((f) async => base64Encode(await f.readAsBytes())),
    );

    final uri = Uri.parse('$_baseUrl/fingerprint/liveness-check');

    late http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'frames': base64Frames}),
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const FingerprintException(
        'Liveness check timed out. Please try again.',
        kind: FingerprintErrorKind.network,
      );
    } on SocketException {
      throw const FingerprintException(
        'No internet connection. Check your network.',
        kind: FingerprintErrorKind.network,
      );
    } catch (_) {
      throw const FingerprintException(
        'Could not reach the server.',
        kind: FingerprintErrorKind.network,
      );
    }

    late Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw FingerprintException(
        'Unexpected server response (${response.statusCode}).',
        statusCode: response.statusCode,
        kind: FingerprintErrorKind.invalidResponse,
      );
    }

    if (response.statusCode == 200) {
      return FingerprintLivenessResult.fromJson(json);
    }

    final msg = _extractMessage(json);
    throw FingerprintException(
      msg,
      statusCode: response.statusCode,
      kind: _kindFromStatus(response.statusCode, msg),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// POST a JSON body with auth headers. Uses a longer timeout than the
  /// multipart sender: hand requests segment + embed 4 fingers server-side.
  Future<http.Response> _postJson(
    Uri uri, {
    required String token,
    required Map<String, dynamic> body,
  }) async {
    try {
      return await http
          .post(
            uri,
            headers: {
              ..._authHeaders(token),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
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

  /// Decode a non-streamed response body as JSON, raising a typed
  /// [FingerprintException] on an empty body or non-JSON (e.g. HTML) response.
  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.body.isEmpty) {
      throw FingerprintException(
        'The server returned an empty response (${response.statusCode}).',
        statusCode: response.statusCode,
        kind: response.statusCode >= 500
            ? FingerprintErrorKind.serverError
            : FingerprintErrorKind.invalidResponse,
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw FingerprintException(
        response.statusCode >= 500
            ? 'Server error (${response.statusCode}). Please try again later.'
            : 'Unexpected response from the server (${response.statusCode}).',
        statusCode: response.statusCode,
        kind: response.statusCode >= 500
            ? FingerprintErrorKind.serverError
            : FingerprintErrorKind.invalidResponse,
      );
    }
  }

  /// Read [image] and re-encode it as a payload-safe JPEG: the camera captures
  /// at high resolution and the raw JPEG can exceed the server's upload limit,
  /// so we downscale the longest edge to <= 1280 px (the processing pipeline
  /// downsamples anyway, so ridge detail is preserved) and step the JPEG
  /// quality down until the payload is comfortably under the limit. Falls back
  /// to the raw bytes when the image can't be decoded.
  Future<List<int>> _compressedJpegBytes(File image) async {
    final raw = await image.readAsBytes();

    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;

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

    return jpg;
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
      if (lower.contains('quality') || lower.contains('usable fingers')) {
        return FingerprintErrorKind.qualityTooLow;
      }
      if (lower.contains('feature') || lower.contains('fingerprint')) {
        return FingerprintErrorKind.noFeatures;
      }
    }

    return FingerprintErrorKind.unknown;
  }
}
