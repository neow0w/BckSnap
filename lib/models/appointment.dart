class Appointment {
  final int id;
  final DateTime scheduledAt; // local time
  final bool isOnline; // false = physical visit
  final String status; // pending / approved / declined
  final String? notes;

  const Appointment({
    required this.id,
    required this.scheduledAt,
    required this.isOnline,
    required this.status,
    this.notes,
  });

  // Fig 8: "Is the appointment approved?"
  bool get isApproved => status == 'approved';
  bool get isDeclined => status == 'declined';
  bool get isPending => !isApproved && !isDeclined;

  // FIELD NAMES: if your API uses different JSON keys, change them here.
  factory Appointment.fromJson(Map<String, dynamic> json) {
    final mode = (json['mode'] ?? '').toString().toLowerCase();
    final online = json['is_online'] is bool
        ? json['is_online'] as bool
        : mode == 'online';
    return Appointment(
      id: json['id'] as int,
      scheduledAt: _parseUtc(json['scheduled_at'] as String),
      isOnline: online,
      status: (json['status'] as String).toLowerCase(),
      notes: json['notes'] as String?,
    );
  }

  // The API stores UTC. If the text has no "Z", treat it as UTC anyway.
  static DateTime _parseUtc(String s) {
    final d = DateTime.parse(s);
    if (d.isUtc) return d.toLocal();
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute,
      d.second,
    ).toLocal();
  }

  String get whenLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = scheduledAt.hour % 12 == 0 ? 12 : scheduledAt.hour % 12;
    final min = scheduledAt.minute.toString().padLeft(2, '0');
    final ap = scheduledAt.hour >= 12 ? 'PM' : 'AM';
    return '${months[scheduledAt.month - 1]} ${scheduledAt.day}, '
        '${scheduledAt.year} · $h:$min $ap';
  }
}
