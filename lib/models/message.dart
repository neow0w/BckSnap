/// One message in a patient <-> clinic thread.
class ChatMessage {
  final int id;
  final String body;
  final bool fromPatient;
  final DateTime createdAt; // local time

  const ChatMessage({
    required this.id,
    required this.body,
    required this.fromPatient,
    required this.createdAt,
  });

  // FIELD NAMES: change the keys here if your API differs.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = (json['sender_role'] ?? '').toString().toLowerCase();
    final fromPatient = json['from_patient'] is bool
        ? json['from_patient'] as bool
        : (role == 'user' || role == 'patient');
    return ChatMessage(
      id: json['id'] as int,
      body: (json['body'] ?? '') as String,
      fromPatient: fromPatient,
      createdAt: parseUtc(json['created_at'] as String),
    );
  }
}

/// One row of the receptionist's inbox (one patient conversation).
class InboxItem {
  final int patientId;
  final String patientName;
  final String lastMessage;
  final DateTime? lastAt;

  const InboxItem({
    required this.patientId,
    required this.patientName,
    required this.lastMessage,
    this.lastAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    final at = json['last_at'] ?? json['created_at'];
    return InboxItem(
      patientId: (json['patient_id'] ?? json['id']) as int,
      patientName: (json['patient_name'] ?? json['name'] ?? 'Patient')
          .toString(),
      lastMessage: (json['last_message'] ?? json['body'] ?? '').toString(),
      lastAt: at is String ? parseUtc(at) : null,
    );
  }
}

/// The API stores UTC. If the text has no "Z", treat it as UTC anyway.
DateTime parseUtc(String s) {
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

String timeLabel(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day}/${d.month} $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}
