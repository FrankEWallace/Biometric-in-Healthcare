class PatientModel {
  final int id;
  final String fullName;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? jmbg;
  final bool isActive;
  final bool isEnrolled;

  const PatientModel({
    required this.id,
    required this.fullName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.jmbg,
    this.isActive = true,
    this.isEnrolled = false,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      gender: json['gender'] as String?,
      jmbg: json['jmbg'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isEnrolled: json['is_enrolled'] as bool? ?? false,
    );
  }
}
