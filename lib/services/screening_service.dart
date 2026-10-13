import 'dart:math';
import 'dart:typed_data';

import 'api_client.dart';

class ScreeningSubmission {
  ScreeningSubmission({
    required this.angle,
    required this.idempotencyKey,
    this.photoBytes,
    this.photoName,
  });

  factory ScreeningSubmission.create({
    required double angle,
    Uint8List? photoBytes,
    String? photoName,
  }) {
    final random = Random.secure();
    final key = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return ScreeningSubmission(
      angle: angle,
      idempotencyKey: key,
      photoBytes: photoBytes,
      photoName: photoName,
    );
  }

  final double angle;
  final String idempotencyKey;
  final Uint8List? photoBytes;
  final String? photoName;
}

class ScreeningService {
  ScreeningService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<int> saveScreening({required ScreeningSubmission submission}) async {
    final data = await _api.postMultipart(
      '/screenings',
      fields: {'angle': submission.angle.toString()},
      fileBytes: submission.photoBytes,
      fileName: submission.photoName,
      headers: {'Idempotency-Key': submission.idempotencyKey},
    );
    if (data is Map<String, dynamic> && data['id'] is int) {
      return data['id'] as int;
    }
    throw ApiException(
      502,
      'The server did not confirm that the screening result was saved.',
    );
  }
}
