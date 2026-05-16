import 'patient.dart';

class VisitStageModel {
  final int id;
  final int visitId;
  final String stage;
  final String status; // pending | completed
  final String? verifiedAt;
  final Map<String, dynamic>? simulatedData;
  final Map<String, dynamic>? verifiedBy;

  const VisitStageModel({
    required this.id,
    required this.visitId,
    required this.stage,
    required this.status,
    this.verifiedAt,
    this.simulatedData,
    this.verifiedBy,
  });

  bool get isCompleted => status == 'completed';
  bool get isPending   => status == 'pending';

  String get stageLabel => switch (stage) {
    'clerk_checkin'  => 'Check-in',
    'triage'         => 'Triage',
    'consultation'   => 'Consultation',
    'laboratory'     => 'Laboratory',
    'pharmacy'       => 'Pharmacy',
    'clerk_checkout' => 'Checkout',
    _                => stage,
  };

  factory VisitStageModel.fromJson(Map<String, dynamic> json) {
    return VisitStageModel(
      id:            json['id'] as int,
      visitId:       json['visit_id'] as int,
      stage:         json['stage'] as String,
      status:        json['status'] as String,
      verifiedAt:    json['verified_at'] as String?,
      simulatedData: json['simulated_data'] as Map<String, dynamic>?,
      verifiedBy:    json['verified_by'] as Map<String, dynamic>?,
    );
  }
}

class VisitModel {
  final int id;
  final int patientId;
  final String visitType; // pending | opd | ipd
  final String status;    // open | closed
  final String openedAt;
  final String? closedAt;
  final int reopenCount;
  final PatientModel? patient;
  final List<VisitStageModel> stages;
  final Map<String, dynamic>? openedBy;

  const VisitModel({
    required this.id,
    required this.patientId,
    required this.visitType,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.reopenCount = 0,
    this.patient,
    this.stages = const [],
    this.openedBy,
  });

  bool get isOpen   => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isPending => visitType == 'pending';

  String get visitTypeLabel => switch (visitType) {
    'opd' => 'OPD',
    'ipd' => 'IPD',
    _     => 'Pending',
  };

  // Returns completed stages in order
  List<VisitStageModel> get completedStages =>
      stages.where((s) => s.isCompleted).toList();

  // Returns the stage record for a given stage name
  VisitStageModel? stageByName(String name) =>
      stages.where((s) => s.stage == name).firstOrNull;

  factory VisitModel.fromJson(Map<String, dynamic> json) {
    final stagesJson = json['stages'] as List<dynamic>? ?? [];
    final patientJson = json['patient'] as Map<String, dynamic>?;
    return VisitModel(
      id:          json['id'] as int,
      patientId:   json['patient_id'] as int,
      visitType:   json['visit_type'] as String? ?? 'pending',
      status:      json['status'] as String? ?? 'open',
      openedAt:    json['opened_at'] as String,
      closedAt:    json['closed_at'] as String?,
      reopenCount: json['reopen_count'] as int? ?? 0,
      patient:     patientJson != null ? PatientModel.fromJson(patientJson) : null,
      stages:      stagesJson.map((s) => VisitStageModel.fromJson(s as Map<String, dynamic>)).toList(),
      openedBy:    json['opened_by'] as Map<String, dynamic>?,
    );
  }
}
