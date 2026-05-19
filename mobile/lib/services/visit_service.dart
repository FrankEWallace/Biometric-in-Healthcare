import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/patient.dart';
import '../models/visit.dart';

class VisitException implements Exception {
  final String message;
  final int? statusCode;
  const VisitException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class VisitService {
  static const String _baseUrl = 'http://192.168.100.144:8000/api';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ── Patient search (for clerk pre-checkin) ───────────────────────────────

  Future<List<PatientModel>> searchPatients({
    required String token,
    required String query,
  }) async {
    late http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl/visits/patient-search')
          .replace(queryParameters: {'q': query});
      response = await http.get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['patients'] as List<dynamic>? ?? [];
      return list.map((p) => PatientModel.fromJson(p as Map<String, dynamic>)).toList();
    }
    throw VisitException('Search failed (${response.statusCode}).',
        statusCode: response.statusCode);
  }

  // ── Open a visit ─────────────────────────────────────────────────────────

  Future<VisitModel> openVisit({
    required String token,
    required int patientId,
    required int verificationLogId,
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    late http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/visits'),
        headers: _headers(token),
        body: jsonEncode({
          'patient_id':           patientId,
          'verification_log_id':  verificationLogId,
          if (gpsLatitude != null)  'gps_latitude':  gpsLatitude,
          if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
          if (wifiSsid != null)     'wifi_ssid':     wifiSsid,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return VisitModel.fromJson(body['visit'] as Map<String, dynamic>);
    }
    if (response.statusCode == 409) {
      throw VisitException(
        body['error'] as String? ?? 'Patient already has an open visit.',
        statusCode: 409,
      );
    }
    throw VisitException(
      body['error'] as String? ?? body['message'] as String? ?? 'Failed to open visit.',
      statusCode: response.statusCode,
    );
  }

  // ── Visit history (admin — closed visits, optional date filter) ──────────

  Future<List<VisitModel>> getVisitHistory({
    required String token,
    String? date, // 'YYYY-MM-DD'
  }) async {
    late http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl/visits').replace(
        queryParameters: {
          'status': 'closed',
          if (date != null) 'date': date,
        },
      );
      response = await http.get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['visits'] as List<dynamic>? ?? [];
      return list.map((v) => VisitModel.fromJson(v as Map<String, dynamic>)).toList();
    }
    throw VisitException('Failed to load history (${response.statusCode}).');
  }

  // ── List visits / queue ───────────────────────────────────────────────────

  Future<List<VisitModel>> getQueue({required String token}) async {
    late http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_baseUrl/queue'),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['queue'] as List<dynamic>? ?? [];
      return list.map((v) => VisitModel.fromJson(v as Map<String, dynamic>)).toList();
    }
    throw VisitException('Failed to load queue (${response.statusCode}).');
  }

  // ── Get a single visit with stages ────────────────────────────────────────

  Future<VisitModel> getVisit({
    required String token,
    required int visitId,
  }) async {
    late http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_baseUrl/visits/$visitId'),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitModel.fromJson(body['visit'] as Map<String, dynamic>);
    }
    throw VisitException('Failed to load visit (${response.statusCode}).');
  }

  // ── Verify patient at a stage ─────────────────────────────────────────────

  Future<Map<String, dynamic>> verifyStage({
    required String token,
    required int visitId,
    required String stage,
    required String fingerprintImage,
    String? faceImage,
    double? gpsLatitude,
    double? gpsLongitude,
    String? wifiSsid,
  }) async {
    late http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/visits/$visitId/stages/$stage/verify'),
        headers: _headers(token),
        body: jsonEncode({
          'fingerprint_image': fingerprintImage,
          if (faceImage != null)    'face_image':    faceImage,
          if (gpsLatitude != null)  'gps_latitude':  gpsLatitude,
          if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
          if (wifiSsid != null)     'wifi_ssid':     wifiSsid,
        }),
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) return body;

    throw VisitException(
      body['message'] as String? ?? body['error'] as String? ?? 'Verification failed.',
      statusCode: response.statusCode,
    );
  }

  // ── Close a visit ─────────────────────────────────────────────────────────

  Future<VisitModel> closeVisit({
    required String token,
    required int visitId,
    required int verificationLogId,
  }) async {
    late http.Response response;
    try {
      response = await http.put(
        Uri.parse('$_baseUrl/visits/$visitId/close'),
        headers: _headers(token),
        body: jsonEncode({'verification_log_id': verificationLogId}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return VisitModel.fromJson(body['visit'] as Map<String, dynamic>);
    }
    throw VisitException(
      body['error'] as String? ?? 'Failed to close visit.',
      statusCode: response.statusCode,
    );
  }

  // ── Reopen a visit ────────────────────────────────────────────────────────

  Future<VisitModel> reopenVisit({
    required String token,
    required int visitId,
    required String reason,
  }) async {
    late http.Response response;
    try {
      response = await http.put(
        Uri.parse('$_baseUrl/visits/$visitId/reopen'),
        headers: _headers(token),
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return VisitModel.fromJson(body['visit'] as Map<String, dynamic>);
    }
    throw VisitException(
      body['error'] as String? ?? 'Failed to reopen visit.',
      statusCode: response.statusCode,
    );
  }

  // ── Request supervisor override ───────────────────────────────────────────

  Future<Map<String, dynamic>> requestOverride({
    required String token,
    required int visitStageId,
    required String fallbackChain,
    String? staffNote,
  }) async {
    late http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/supervisor-overrides'),
        headers: _headers(token),
        body: jsonEncode({
          'visit_stage_id': visitStageId,
          'fallback_chain': fallbackChain,
          if (staffNote != null) 'staff_note': staffNote,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return body;
    throw VisitException(
      body['error'] as String? ?? 'Failed to request override.',
      statusCode: response.statusCode,
    );
  }

  // ── List supervisor overrides ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPendingOverrides({
    required String token,
  }) async {
    late http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_baseUrl/supervisor-overrides'),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['overrides'] as List<dynamic>? ?? [];
      return list.cast<Map<String, dynamic>>();
    }
    throw VisitException('Failed to load overrides (${response.statusCode}).');
  }

  // ── Resolve a supervisor override ─────────────────────────────────────────

  Future<void> resolveOverride({
    required String token,
    required int overrideId,
    required String decision,
    String? note,
  }) async {
    late http.Response response;
    try {
      response = await http.put(
        Uri.parse('$_baseUrl/supervisor-overrides/$overrideId/resolve'),
        headers: _headers(token),
        body: jsonEncode({
          'decision': decision,
          if (note != null && note.isNotEmpty) 'supervisor_note': note,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) return;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw VisitException(
      body['error'] as String? ?? 'Failed to resolve override.',
      statusCode: response.statusCode,
    );
  }

  // ── Update simulated data for a stage ────────────────────────────────────

  Future<void> updateStageData({
    required String token,
    required int visitId,
    required String stage,
    required Map<String, dynamic> simulatedData,
  }) async {
    late http.Response response;
    try {
      response = await http.put(
        Uri.parse('$_baseUrl/visits/$visitId/stages/$stage/data'),
        headers: _headers(token),
        body: jsonEncode({'simulated_data': simulatedData}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VisitException('Could not reach the server.');
    }

    if (response.statusCode == 200) return;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw VisitException(
      body['error'] as String? ?? 'Failed to save data.',
      statusCode: response.statusCode,
    );
  }
}
