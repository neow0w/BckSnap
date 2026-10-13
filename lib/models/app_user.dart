class AppUser {
  final int id;
  final String? name;
  final String? firstName;
  final String? middleInitial;
  final String? lastName;
  final DateTime? birthdate;
  final String? address;
  final String? gender;
  final String? contactNumber;
  final String? email;
  final String role; // user / receptionist / doctor
  final bool isGuest;

  const AppUser({
    required this.id,
    required this.name,
    this.firstName,
    this.middleInitial,
    this.lastName,
    this.birthdate,
    this.address,
    this.gender,
    this.contactNumber,
    required this.email,
    required this.role,
    required this.isGuest,
  });

  String? get displayName {
    final first = firstName?.trim();
    final last = lastName?.trim();
    if (first != null && first.isNotEmpty && last != null && last.isNotEmpty) {
      final middle = middleInitial?.trim();
      return [
        first,
        if (middle != null && middle.isNotEmpty)
          '${middle.replaceAll('.', '')}.',
        last,
      ].join(' ');
    }
    return name;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String?,
    firstName: json['first_name'] as String?,
    middleInitial: json['middle_initial'] as String?,
    lastName: json['last_name'] as String?,
    birthdate: json['birthdate'] == null
        ? null
        : DateTime.parse(json['birthdate'] as String),
    address: json['address'] as String?,
    gender: json['gender'] as String?,
    contactNumber: json['contact_number'] as String?,
    email: json['email'] as String?,
    role: json['role'] as String,
    isGuest: json['is_guest'] as bool,
  );
}
