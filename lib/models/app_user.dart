import '../core/validators.dart';

class AppUser {
  final int id;
  final String? name;
  final String? email;
  final String role; // user / receptionist / doctor
  final bool isGuest;

  // Account details (new)
  final String? phone;
  final DateTime? dateOfBirth;
  final String? address;
  final bool hasPhoto; // true when a profile picture is stored on the server

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isGuest,
    this.phone,
    this.dateOfBirth,
    this.address,
    this.hasPhoto = false,
  });

  /// Name to greet the user with (falls back to the email).
  String? get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = email?.trim();
    return (e != null && e.isNotEmpty) ? e : null;
  }

  int? get age => dateOfBirth == null
      ? null
      : Validators.ageOn(dateOfBirth!, DateTime.now());

  // FIELD NAMES: change the keys here if your API uses different ones.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    final dob = json['date_of_birth'];
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String,
      isGuest: json['is_guest'] as bool,
      phone: json['phone'] as String?,
      dateOfBirth: dob is String ? DateTime.tryParse(dob) : null,
      address: json['address'] as String?,
      hasPhoto: json['has_photo'] == true,
    );
  }
}
