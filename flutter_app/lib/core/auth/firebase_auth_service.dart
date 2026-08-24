import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:music_hub_app/core/config/app_config.dart';

class FirebaseAuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  final GoogleSignIn _google = GoogleSignIn.instance;
  bool _initialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    await _google.initialize(
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );
    _initialized = true;
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      return _auth.signInWithPopup(GoogleAuthProvider());
    }
    await initialize();
    final account = await _google.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in account');
    if (kIsWeb) {
      return user.reauthenticateWithPopup(GoogleAuthProvider());
    }
    await initialize();
    final account = await _google.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return user.reauthenticateWithCredential(credential);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && _initialized) await _google.signOut();
  }

  Future<void> deleteCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in account');
    await user.delete();
    if (!kIsWeb && _initialized) {
      try {
        await _google.signOut();
      } catch (_) {
        // The Firebase account is already deleted; local Google cleanup is
        // best-effort and must not make deletion appear to have failed.
      }
    }
  }
}
