import '../models/appointment.dart';
import 'api_client.dart';

/// Patient-side calls for Figure 8.
///
/// FIELD NAMES in the request bodies below are my best guess. If your
/// FastAPI schemas use other names, change them here (this is the only file
/// that builds these requests).
class AppointmentService {
  final ApiClient _api = ApiClient.instance;

  /// GET /appointments/mine
  Future<List<Appointment>> mine() async {
    final data = await _api.get('/appointments/mine') as List;
    return [
      for (final e in data) Appointment.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// POST /appointments
  Future<void> book({
    required DateTime when,
    required bool online,
    String? notes,
  }) async {
    await _api.post(
      '/appointments',
      body: {
        'scheduled_at': when.toUtc().toIso8601String(),
        'mode': online ? 'online' : 'physical',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// GET /appointments/{id}/room  (connector D)
  /// Returns the room link/name, or null if the API gave nothing usable.
  Future<String?> room(int appointmentId) async {
    final data = await _api.get('/appointments/$appointmentId/room');
    if (data is Map) {
      final v = data['url'] ?? data['room_url'] ?? data['room'];
      return v?.toString();
    }
    return data?.toString();
  }

  /// POST /messages  ("Send a message to the clinic")
  Future<void> sendMessage(String body) async {
    await _api.post('/messages', body: {'body': body});
  }
}
