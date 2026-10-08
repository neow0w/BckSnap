import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  // A guest is anyone not logged in, or logged in anonymously.
  bool get isGuest => currentUser == null || currentUser!.isAnonymous;

  // Fig 7: a new visitor screens as a guest (temporary anonymous account).
  Future<void> signInAsGuest() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  // Fig 7: Sign up. If the user is a guest, the guest account is upgraded,
  // so the screening they already did is kept.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final UserCredential result;
    final current = _auth.currentUser;

    if (current != null && current.isAnonymous) {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      result = await current.linkWithCredential(credential);
    } else {
      result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }

    // Save the profile in the database (the "User Information DB").
    await _db.collection('users').doc(result.user!.uid).set({
      'name': name,
      'email': email,
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Fig 7: Login
  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Fig 7: Reset password -> "Password reset email sent"
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  // Fig 7: "Is the user an admin?"
  // Returns 'user', 'receptionist', or 'doctor'.
  Future<String> getRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'user';
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['role'] as String?) ?? 'user';
  }
}
