import '../models/message.dart';
import 'api_client.dart';

/// Patient <-> clinic messages.
/// Patient side: sendMessage. Receptionist side: inbox, thread, reply.
///
/// FIELD NAMES in request bodies are a best guess; change them here if your
/// FastAPI schemas differ (for example if /messages needs a clinic_id).
class MessageService {
  final ApiClient _api = ApiClient.instance;

  /// POST /messages  ("Send a message to the clinic")
  Future<void> sendMessage(String body) async {
    await _api.post('/messages', body: {'body': body});
  }

  /// GET /messages/mine
  /// Loads the patient's conversation with the clinic.
  Future<List<ChatMessage>> getMyMessages() async {
    final data = await _api.get('/messages/mine') as List;

    final messages = [
      for (final item in data)
        ChatMessage.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
    ];

    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// GET /messages/inbox
  Future<List<InboxItem>> inbox() async {
    final data = await _api.get('/messages/inbox') as List;
    return [
      for (final e in data) InboxItem.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// GET /messages/patient/{patient_id}
  Future<List<ChatMessage>> thread(int patientId) async {
    final data = await _api.get('/messages/patient/$patientId') as List;
    final list = [
      for (final e in data) ChatMessage.fromJson(e as Map<String, dynamic>),
    ];
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// POST /messages/patient/{patient_id}
  Future<void> reply(int patientId, String body) async {
    await _api.post('/messages/patient/$patientId', body: {'body': body});
  }
}
