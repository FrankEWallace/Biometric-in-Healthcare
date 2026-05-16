class PatientModel {
  final int id;
  final String fullName;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? nida;
  final String? hospitalPatientId;
  final bool isActive;
  final bool isEnrolled;
  final bool hasOpenVisit;

  const PatientModel({
    required this.id,
    required this.fullName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.nida,
    this.hospitalPatientId,
    this.isActive = true,
    this.isEnrolled = false,
    this.hasOpenVisit = false,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id:                json['id'] as int,
      fullName:          json['full_name'] as String,
      phone:             json['phone'] as String?,
      dateOfBirth:       json['date_of_birth'] as String?,
      gender:            json['gender'] as String?,
      nida:              json['nida'] as String?,
      hospitalPatientId: json['hospital_patient_id'] as String?,
      isActive:          json['is_active'] as bool? ?? true,
      isEnrolled:        json['is_enrolled'] as bool? ?? false,
      hasOpenVisit:      json['has_open_visit'] as bool? ?? false,
    );
  }

  String get displayId => hospitalPatientId ?? 'ID #$id';
}
