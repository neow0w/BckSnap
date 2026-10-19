import 'dart:typed_data';

import '../core/format.dart';
import '../models/app_user.dart';
import 'api_client.dart';

class AuthService {
  // One shared instance, so every screen sees the same logged-in user.
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final ApiClient _api = ApiClient.instance;
  AppUser? _user;
  Map<String, dynamic>? _clinic;

  AppUser? get currentUser => _user;
  Map<String, dynamic>? get currentClinic => _clinic;
  bool get isClinicLoggedIn => _clinic != null;

  // A guest is anyone not logged in, or using a guest account.
  bool get isGuest => _user == null || _user!.isGuest;

  /// Runs once when the app starts: restores the saved login, if any.
  Future<void> init() async {
    try {
      await _api.loadToken();
      if (!_api.hasToken) return;

      if (_api.accountType == 'clinic') {
        await _refreshClinic();
      } else {
        await _refresh();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _api.clearToken();
        _user = null;
        _clinic = null;
      }
    } catch (_) {
      // The app can still open if startup restoration fails.
    }
  }

  Future<void> _refresh() async {
    try {
      final data = await _api.get('/auth/me');
      _user = AppUser.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _api.clearToken(); // saved token expired or invalid
        _user = null;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _refreshClinic() async {
    try {
      final data = await _api.get('/auth/clinic/me');
      _clinic = Map<String, dynamic>.from(data as Map);
      _user = null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _api.clearToken();
        _clinic = null;
        _user = null;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _apply(dynamic data) async {
    final map = data as Map<String, dynamic>;
    await _api.saveToken(map['access_token'] as String, accountType: 'user');

    _user = AppUser.fromJson(map['user'] as Map<String, dynamic>);
    _clinic = null;
  }

  // Fig 7: a new visitor screens as a guest (temporary account).
  Future<void> signInAsGuest() async {
    if (_user != null) return;
    if (_api.hasToken) {
      await _refresh();
      if (_user != null) return;
    }
    await _apply(await _api.post('/auth/guest'));
  }

  // Fig 7: Sign up. The API upgrades the guest account, so the
  // screening the guest already did is kept.
  //
  // Consent is sent with the account so the server can store it as a record.
  // For ages 9-17 the guardian and assent fields are filled in.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    required String privacyVersion,
    String? guardianName,
    String? guardianRelationship,
    String? guardianContact,
    bool guardianConsent = false,
    bool minorAssent = false,
  }) async {
    await _apply(
      await _api.post(
        '/auth/signup',
        body: {
          'name': name,
          'email': email,
          'password': password,
          'date_of_birth': isoDate(dateOfBirth),
          'privacy_notice_version': privacyVersion,
          'privacy_consent': true,
          'health_data_consent': true,
          'consented_at': DateTime.now().toUtc().toIso8601String(),
          'guardian_name': ?guardianName,
          'guardian_relationship': ?guardianRelationship,
          'guardian_contact': ?guardianContact,
          'guardian_consent': guardianConsent,
          'minor_assent': minorAssent,
        },
      ),
    );
  }

  // Fig 7: Login
  Future<void> login({
    required String email,
    required String password,
    bool isClinic = false,
  }) async {
    final endpoint = isClinic ? '/auth/clinic/login' : '/auth/login';

    final data = await _api.post(
      endpoint,
      body: {'email': email, 'password': password},
    );

    final map = Map<String, dynamic>.from(data as Map);

    await _api.saveToken(
      map['access_token'] as String,
      accountType: isClinic ? 'clinic' : 'user',
    );

    if (isClinic) {
      _clinic = Map<String, dynamic>.from(map['clinic'] as Map);
      _user = null;
    } else {
      _user = AppUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      _clinic = null;
    }
  }

  // Fig 7: Reset password, step 1 -> "Password reset email sent"
  Future<void> resetPassword(String email) async {
    await _api.post('/auth/forgot-password', body: {'email': email});
  }

  // Reset password, step 2: the code from the email + the new password.
  // FIELD NAMES: change 'token' / 'new_password' if your API differs.
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: {'token': token, 'new_password': newPassword},
    );
  }

  // ---- profile --------------------------------------------------------

  /// PATCH /auth/me. Empty phone/address are sent as null (= cleared).
  Future<void> updateProfile({
    required String name,
    String? phone,
    String? address,
  }) async {
    final data = await _api.patch(
      '/auth/me',
      body: {'name': name, 'phone': phone, 'address': address},
    );
    if (data is Map<String, dynamic> && data.containsKey('id')) {
      _user = AppUser.fromJson(data);
    } else {
      await _refresh();
    }
  }

  /// POST /auth/me/photo (multipart, field name "photo")
  Future<void> uploadPhoto(Uint8List bytes, String fileName) async {
    await _api.postMultipart(
      '/auth/me/photo',
      fileField: 'photo',
      fileBytes: bytes,
      fileName: fileName,
    );
    await _refresh();
  }

  /// GET /auth/me/photo. Null when there is no picture (or it failed).
  Future<Uint8List?> loadMyPhoto() async {
    if (_user?.hasPhoto != true) return null;
    try {
      return await _api.getBytes('/auth/me/photo');
    } on ApiException {
      return null;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    _user = null;
    _clinic = null;
  }

  // Fig 7: "Is the user an admin?"  Returns 'user', 'receptionist' or 'doctor'.
  Future<String> getRole() async => _user?.role ?? 'user';
}
