import '../config/app_config.dart';
import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
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

class FingerprintLivenessResult {
  final bool isLive;
  final double meanDisplacement;
  final int frameCount;
  final String reason;

  const FingerprintLivenessResult({
    required this.isLive,
    required this.meanDisplacement,
    required this.frameCount,
    required this.reason,
  });

  factory FingerprintLivenessResult.fromJson(Map<String, dynamic> json) {
    return FingerprintLivenessResult(
      isLive:          json['is_live']           as bool?   ?? false,
      meanDisplacement:(json['mean_displacement'] as num?)?.toDouble() ?? 0.0,
      frameCount:      json['frame_count']        as int?    ?? 0,
      reason:          json['reason']             as String? ?? 'unknown',
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
  final int?   verificationLogId; // ID of the created VerificationLog record

  // GoT-HoMIS enrichment (null when unavailable or no match)
  final Map<String, dynamic>? ehr;
  final Map<String, dynamic>? insurance;

  const FingerprintVerifyResult({
    required this.verdict,
    required this.score,
    required this.probeKeypoints,
    required this.featureStatus,
    required this.patientName,
    required this.patientId,
    required this.matchedFinger,
    this.verificationLogId,
    this.ehr,
    this.insurance,
  });

  bool get isMatch => verdict == 'MATCH';

  factory FingerprintVerifyResult.fromJson(Map<String, dynamic> json) {
    final patient = json['patient'] as Map<String, dynamic>? ?? {};
    return FingerprintVerifyResult(
      verdict:             json['verdict']              as String? ?? 'NO MATCH',
      score:               (json['score'] as num?)?.toDouble() ?? 0.0,
      probeKeypoints:      json['probe_keypoints']      as int?    ?? 0,
      featureStatus:       json['feature_status']       as String? ?? 'unknown',
      verificationLogId:   json['verification_log_id']  as int?,
      patientName:         patient['full_name']         as String? ?? 'Unknown',
      patientId:           patient['id']                as int?    ?? 0,
      matchedFinger:       json['matched_finger']       as String? ?? '',
      ehr:                 json['ehr']       as Map<String, dynamic>?,
      insurance:           json['insurance'] as Map<String, dynamic>?,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class FingerprintService {
  static const String _baseUrl = AppConfig.baseUrl;

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

    request.files.add(await _imageUploadPart(image));

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
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    final uri = Uri.parse('$_baseUrl/fingerprint/verify');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(token))
      ..fields['patient_id'] = patientId;

    if (gpsLatitude  != null) request.fields['gps_latitude']  = gpsLatitude.toString();
    if (gpsLongitude != null) request.fields['gps_longitude'] = gpsLongitude.toString();
    if (wifiSsid     != null) request.fields['wifi_ssid']     = wifiSsid;

    request.files.add(await _imageUploadPart(image));

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

  /// Build the multipart part for a captured fingerprint image.
  ///
  /// The camera captures at high resolution and the raw JPEG can exceed the
  /// server's PHP upload limit (`upload_max_filesize`), which makes the dev
  /// server reset the connection mid-upload — surfacing to the user as a
  /// generic "Could not reach the server". To avoid that we re-encode here:
  /// downscale the longest edge to <= 1280 px (the processing pipeline
  /// downsamples anyway, so ridge detail is preserved) and step the JPEG
  /// quality down until the payload is comfortably under the limit.
  ///
  /// If the bytes can't be decoded we fall back to sending them unchanged.
  Future<http.MultipartFile> _imageUploadPart(File image) async {
    final raw = await image.readAsBytes();

    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      return http.MultipartFile.fromBytes(
        'fingerprint',
        raw,
        filename: 'fingerprint.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
    }

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

    return http.MultipartFile.fromBytes(
      'fingerprint',
      jpg,
      filename: 'fingerprint.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
  }

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
