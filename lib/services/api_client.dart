import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown whenever the API (or the network) fails.
/// [message] is always safe to show to the user.
class ApiException implements Exception {
  final int statusCode; // 0 = could not reach the server
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client(),
       _configuredBaseUrl = baseUrl;

  static final ApiClient instance = ApiClient();

  static const String _tokenKey = 'access_token';
  static const String _apiBaseOverride = String.fromEnvironment(
    'BCKSNAP_API_BASE_URL',
  );

  final http.Client _httpClient;
  final String? _configuredBaseUrl;
  final Duration requestTimeout;

  /// Where the API lives.
  /// - Chrome / web: your own PC
  /// - Android emulator: 10.0.2.2 is the emulator's name for your PC
  /// - A physical Android device needs the computer's reachable LAN address
  static String get baseUrl {
    return _resolveBaseUrl(_apiBaseOverride);
  }

  static String get diagnosticOrigin {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority) return 'invalid API origin';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  String get _effectiveBaseUrl =>
      _configuredBaseUrl ?? _resolveBaseUrl(_apiBaseOverride);

  static String _resolveBaseUrl(String override) {
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  String? _token;
  String? get token => _token;
  bool get hasToken => _token != null;

  // ---- token storage ----------------------------------------------------

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ---- requests ---------------------------------------------------------

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Uri _uri(String path) {
    final origin = _effectiveBaseUrl.endsWith('/')
        ? _effectiveBaseUrl.substring(0, _effectiveBaseUrl.length - 1)
        : _effectiveBaseUrl;
    return Uri.parse('$origin${path.startsWith('/') ? path : '/$path'}');
  }

  Future<dynamic> get(String path) async {
    final res = await _send(
      () => _httpClient.get(_uri(path), headers: _headers()),
    );
    return _decode(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final res = await _send(
      () => _httpClient.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? {}),
      ),
    );
    return _decode(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final res = await _send(
      () => _httpClient.patch(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? {}),
      ),
    );
    return _decode(res);
  }

  /// For uploads such as the back photo (form fields + an optional file).
  Future<dynamic> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    String fileField = 'photo',
    Uint8List? fileBytes,
    String? fileName,
    Map<String, String> headers = const {},
  }) async {
    final res = await _send(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers.addAll(_headers());
      request.headers.addAll(headers);
      request.fields.addAll(fields);
      if (fileBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            fileBytes,
            filename: fileName ?? 'photo.jpg',
          ),
        );
      }
      final streamed = await _httpClient.send(request);
      return http.Response.fromStream(streamed);
    });
    return _decode(res);
  }

  /// For downloading private files such as a patient's photo.
  Future<Uint8List> getBytes(String path) async {
    final res = await _send(
      () => _httpClient.get(_uri(path), headers: _headers()),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res));
    }
    return res.bodyBytes;
  }

  // ---- helpers ----------------------------------------------------------

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException(
        408,
        'The request timed out while connecting to $diagnosticOrigin. '
        'For a physical phone, '
        'use the laptop LAN address, run Uvicorn with --host 0.0.0.0, and '
        'check the local firewall and wired-to-wireless network path.',
      );
    } on http.ClientException {
      throw ApiException(
        0,
        'Cannot reach the BckSnap server. Check the API address, that the backend is running, and that your phone and computer are on the same Wi-Fi network.',
      );
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res));
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(
        502,
        'The server returned an invalid response. Please retry or contact the server administrator.',
      );
    }
  }

  /// FastAPI errors look like {"detail": "text"} or, for validation
  /// problems, {"detail": [{"msg": "..."}]}.
  String _errorMessage(http.Response res) {
    if (res.statusCode == 401) {
      return 'Your session has expired or you need to sign in. Please sign in and retry.';
    }
    if (res.statusCode == 403) {
      return 'Your account is not authorized to perform this action.';
    }
    if (res.statusCode >= 500) {
      return 'The server encountered an error (HTTP ${res.statusCode}). Please retry later.';
    }
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = data is Map ? data['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty && detail.first is Map) {
        return (detail.first as Map)['msg']?.toString() ?? 'Invalid input.';
      }
    } catch (_) {}
    return 'Something went wrong (error ${res.statusCode}). Please try again.';
  }
}
