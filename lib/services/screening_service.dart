import 'dart:typed_data';

import '../models/screening.dart';
import 'api_client.dart';

class ScreeningService {
  final ApiClient _api = ApiClient.instance;

  // Saves one screening to the API, with the back photo if we have one.
  // The server decides has_scoliosis itself, using its 7-degree setting.
  Future<int?> saveScreening({
    required double angle,
    Uint8List? photoBytes,
    String? photoName,
  }) async {
    final data = await _api.postMultipart(
      '/screenings',
      fields: {'angle': angle.toString()},
      fileBytes: photoBytes,
      fileName: photoName,
    ) as Map<String, dynamic>;
    return data['id'] as int?;
  }

  // The logged-in user's screenings, newest first.
  Future<List<Screening>> myScreenings() async {
    final data = await _api.get('/screenings/mine') as List<dynamic>;
    return data
        .map((e) => Screening.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
