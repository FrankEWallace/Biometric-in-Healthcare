class User {
  final int id;
  final String name;
  final String email;
  final String username;
  final String role; // 'nurse' | 'admin' | 'super_admin' | 'doctor'
  final int? hospitalId;
  final String token;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.role,
    required this.hospitalId,
    required this.token,
  });

  bool get isNurse      => role == 'nurse';
  bool get isAdmin      => role == 'admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isDoctor     => role == 'doctor';
  bool get isAnyAdmin   => role == 'admin' || role == 'super_admin';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id:         json['id'] as int,
      name:       json['name'] as String,
      email:      json['email'] as String,
      username:   json['username'] as String? ?? '',
      role:       json['role'] as String? ?? 'nurse',
      hospitalId: json['hospital_id'] as int?,
      token:      json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':          id,
        'name':        name,
        'email':       email,
        'username':    username,
        'role':        role,
        'hospital_id': hospitalId,
        'token':       token,
      };
}
