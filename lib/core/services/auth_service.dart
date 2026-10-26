import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static bool get isLoggedIn => _auth.currentUser != null;

  static Future<String?> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  static Future<String?> registerWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  static Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return 'Autentificare anulată.';

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    } catch (_) {
      return 'Eroare Google Sign-In. Încearcă din nou.';
    }
  }

  static Future<void> updateDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
  }

  static Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  static Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  static String _friendlyError(String code) {
    return switch (code) {
      'user-not-found'       => 'Nu există un cont cu acest email.',
      'wrong-password'       => 'Parolă greșită. Încearcă din nou.',
      'email-already-in-use' => 'Acest email este deja folosit.',
      'invalid-email'        => 'Adresa de email nu este validă.',
      'weak-password'        => 'Parola trebuie să aibă cel puțin 6 caractere.',
      'too-many-requests'    => 'Prea multe încercări. Încearcă mai târziu.',
      'network-request-failed' => 'Eroare de rețea. Verifică conexiunea.',
      'user-disabled'        => 'Acest cont a fost dezactivat.',
      'invalid-credential'   => 'Email sau parolă incorectă.',
      _                      => 'A apărut o eroare. Încearcă din nou.',
    };
  }
}
