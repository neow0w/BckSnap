import '../models/app_user.dart';
import 'api_client.dart';

class AuthService {
  // One shared instance, so every screen sees the same logged-in user.
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final ApiClient _api = ApiClient.instance;
  AppUser? _user;

  AppUser? get currentUser => _user;

  // A guest is anyone not logged in, or using a guest account.
  bool get isGuest => _user == null || _user!.isGuest;

  /// Runs once when the app starts: restores the saved login, if any.
  Future<void> init() async {
    try {
      await _api.loadToken();
      if (_api.hasToken) await _refresh();
    } catch (_) {
      // Server unreachable at startup: the app still opens.
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

  Future<void> _apply(dynamic data) async {
    final map = data as Map<String, dynamic>;
    await _api.saveToken(map['access_token'] as String);
    _user = AppUser.fromJson(map['user'] as Map<String, dynamic>);
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
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await _apply(
      await _api.post(
        '/auth/signup',
        body: {'name': name, 'email': email, 'password': password},
      ),
    );
  }

  // Fig 7: Login
  Future<void> login({required String email, required String password}) async {
    await _apply(
      await _api.post(
        '/auth/login',
        body: {'email': email, 'password': password},
      ),
    );
  }

  // Fig 7: Reset password -> "Password reset email sent"
  Future<void> resetPassword(String email) async {
    await _api.post('/auth/forgot-password', body: {'email': email});
  }

  Future<void> logout() async {
    await _api.clearToken();
    _user = null;
  }

  // Fig 7: "Is the user an admin?"  Returns 'user', 'receptionist' or 'doctor'.
  Future<String> getRole() async => _user?.role ?? 'user';
}
