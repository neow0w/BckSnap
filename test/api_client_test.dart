import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_bcksnap/services/api_client.dart';

void main() {
  test('uses the configured API origin for requests', () async {
    late Uri requestedUri;
    final client = ApiClient(
      baseUrl: 'http://192.168.1.134:8000/',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('[]', 200);
      }),
    );

    expect(await client.get('/clinics'), isEmpty);
    expect(requestedUri.toString(), 'http://192.168.1.134:8000/clinics');
  });

  test('describes expired authentication distinctly', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'detail': 'Not authenticated'}), 401),
      ),
    );

    await expectLater(
      client.get('/clinics'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              contains('session has expired'),
            ),
      ),
    );
  });

  test('describes backend failures distinctly', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((_) async => http.Response('{}', 503)),
    );

    await expectLater(
      client.get('/clinics'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('server encountered an error'),
        ),
      ),
    );
  });

  test('describes an unreachable server distinctly', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient(
        (_) async => throw http.ClientException('Connection refused'),
      ),
    );

    await expectLater(
      client.get('/clinics'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having(
              (error) => error.message,
              'message',
              contains('Cannot reach the BckSnap server'),
            ),
      ),
    );
  });

  test('describes a request timeout distinctly', () async {
    final neverCompletes = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'http://localhost',
      requestTimeout: const Duration(milliseconds: 10),
      httpClient: MockClient((_) => neverCompletes.future),
    );

    await expectLater(
      client.get('/clinics'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 408)
            .having(
              (error) => error.message,
              'message',
              contains('request timed out'),
            ),
      ),
    );
  });
}
