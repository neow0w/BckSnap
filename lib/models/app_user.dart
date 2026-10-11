class AppUser {
  final int id;
  final String? name;
  final String? email;
  final String role; // user / receptionist / doctor
  final bool isGuest;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isGuest,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String?,
    email: json['email'] as String?,
    role: json['role'] as String,
    isGuest: json['is_guest'] as bool,
  );
}
