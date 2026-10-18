class Screening {
  final int id;
  final int userId;
  final double angle;
  final bool hasScoliosis;
  final bool hasPhoto;
  final DateTime createdAt;

  const Screening({
    required this.id,
    required this.userId,
    required this.angle,
    required this.hasScoliosis,
    required this.hasPhoto,
    required this.createdAt,
  });

  factory Screening.fromJson(Map<String, dynamic> json) => Screening(
    id: json['id'] as int,
    userId: json['user_id'] as int,
    angle: (json['angle'] as num).toDouble(),
    hasScoliosis: json['has_scoliosis'] as bool,
    hasPhoto: json['has_photo'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}
