import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_bcksnap/services/api_client.dart';
import 'package:flutter_bcksnap/services/screening_service.dart';

void main() {
  test(
    'posts the result to the configured API using multipart schema',
    () async {
      late Uri requestedUri;
      late String requestBody;
      late String idempotencyKey;
      final submission = ScreeningSubmission(
        angle: 8.5,
        idempotencyKey: 'attempt-key-123',
      );
      final service = ScreeningService(
        api: ApiClient(
          baseUrl: 'http://192.168.1.134:8000',
          httpClient: MockClient((request) async {
            requestedUri = request.url;
            requestBody = String.fromCharCodes(request.bodyBytes);
            idempotencyKey = request.headers['Idempotency-Key']!;
            return http.Response(jsonEncode({'id': 7}), 200);
          }),
        ),
      );

      final id = await service.saveScreening(submission: submission);

      expect(requestedUri.toString(), 'http://192.168.1.134:8000/screenings');
      expect(requestBody, contains('name="angle"'));
      expect(requestBody, contains('8.5'));
      expect(idempotencyKey, submission.idempotencyKey);
      expect(id, 7);
    },
  );

  test('preserves network timeout as a failed save', () async {
    final neverCompletes = Completer<http.Response>();
    final service = ScreeningService(
      api: ApiClient(
        baseUrl: 'http://192.168.1.134:8000',
        requestTimeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) => neverCompletes.future),
      ),
    );

    await expectLater(
      service.saveScreening(submission: ScreeningSubmission.create(angle: 4)),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          408,
        ),
      ),
    );
  });

  test('does not treat an invalid response as a confirmed save', () async {
    final service = ScreeningService(
      api: ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );

    await expectLater(
      service.saveScreening(submission: ScreeningSubmission.create(angle: 4)),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          502,
        ),
      ),
    );
  });

  test('surfaces backend validation responses', () async {
    final service = ScreeningService(
      api: ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': [
                {'msg': 'Invalid angle'},
              ],
            }),
            422,
          ),
        ),
      ),
    );

    await expectLater(
      service.saveScreening(submission: ScreeningSubmission.create(angle: 4)),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having((error) => error.message, 'message', 'Invalid angle'),
      ),
    );
  });
}
