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
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String _tokenKey = 'access_token';
  static const String _accountTypeKey = 'account_type';
  static const Duration _timeout = Duration(seconds: 20);

  // Development: the API runs on your PC. On a phone connected by USB,
  // "adb reverse" makes 127.0.0.1 point to your PC.
  // For a deployed API, build with: --dart-define=API_URL=https://your-api
  static const String _apiOverride = String.fromEnvironment('API_URL');
  static String get baseUrl =>
      _apiOverride.isNotEmpty ? _apiOverride : 'http://127.0.0.1:8000';

  /// Scheme + host + port only (no path, no token). Safe for debug logs.
  static String get diagnosticOrigin {
    try {
      return Uri.parse(baseUrl).origin;
    } catch (_) {
      return 'unknown';
    }
  }

  String? _token;
  String? get token => _token;
  String? _accountType;
  String? get accountType => _accountType;
  bool get hasToken => _token != null;

  // ---- token storage ----------------------------------------------------

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _accountType = prefs.getString(_accountTypeKey);
  }

  Future<void> saveToken(String token, {String accountType = 'user'}) async {
    _token = token;
    _accountType = accountType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_accountTypeKey, accountType);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_accountTypeKey);
  }

  // ---- requests ---------------------------------------------------------

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> get(String path) async {
    final res = await _send(() => http.get(_uri(path), headers: _headers()));
    return _decode(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final res = await _send(
      () => http.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? {}),
      ),
    );
    return _decode(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final res = await _send(
      () => http.patch(
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
  }) async {
    final res = await _send(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers.addAll(_headers());
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
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    return _decode(res);
  }

  /// For downloading private files such as a patient's photo.
  Future<Uint8List> getBytes(String path) async {
    final res = await _send(() => http.get(_uri(path), headers: _headers()));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res));
    }
    return res.bodyBytes;
  }

  // ---- helpers ----------------------------------------------------------

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res));
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// FastAPI errors look like {"detail": "text"} or, for validation
  /// problems, {"detail": [{"msg": "..."}]}.
  String _errorMessage(http.Response res) {
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
