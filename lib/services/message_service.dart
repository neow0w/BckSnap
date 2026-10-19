
import '../models/message.dart';
import 'api_client.dart';

/// Patient <-> clinic messaging, scoped to a specific clinic.
class MessageService {
  final ApiClient _api = ApiClient.instance;

  /// POST /messages/{clinic_id}
  Future<void> sendMessage(int clinicId, String body) async {
    await _api.post(
      '/messages/$clinicId',
      body: {'body': body},
    );
  }

  /// GET /messages/mine/{clinic_id}
  Future<List<ChatMessage>> getMyMessages(int clinicId) async {
    final data = await _api.get('/messages/mine/$clinicId') as List;

    final messages = [
      for (final item in data)
        ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
    ];

    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// GET /messages/inbox
  Future<List<InboxItem>> inbox() async {
    final data = await _api.get('/messages/inbox') as List;
    return [
      for (final e in data)
        InboxItem.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  /// GET /messages/patient/{patient_id}?clinic_id={clinic_id}
  Future<List<ChatMessage>> thread(
    int patientId,
    int clinicId,
  ) async {
    final data = await _api.get(
      '/messages/patient/$patientId?clinic_id=$clinicId',
    ) as List;

    final list = [
      for (final e in data)
        ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
    ];

    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// POST /messages/patient/{patient_id}?clinic_id={clinic_id}
  Future<void> reply(
    int patientId,
    int clinicId,
    String body,
  ) async {
    await _api.post(
      '/messages/patient/$patientId?clinic_id=$clinicId',
      body: {'body': body},
    );
  }
}
