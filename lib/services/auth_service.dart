import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String melcoIdToEmail(String melcoId) => '${melcoId.trim()}@hodw.local';

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> authStateChanges() async* {
    await for (final user in _auth.authStateChanges()) {
      if (user != null && user.isAnonymous) {
        await _auth.signOut();
        yield null;
        continue;
      }
      yield user;
    }
  }

  static Future<UserCredential> signInWithMelcoId({required String melcoId, required String password}) {
    return _auth.signInWithEmailAndPassword(
      email: melcoIdToEmail(melcoId),
      password: password,
    );
  }

  static Future<void> signOut() => _auth.signOut();

  static Future<void> reauthenticateCurrentUser({required String currentPassword}) async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    final melcoId = user.email?.replaceAll('@hodw.local', '').trim();
    if (melcoId == null || melcoId.isEmpty) {
      throw FirebaseAuthException(code: 'missing-melco-id');
    }
    final credential = EmailAuthProvider.credential(
      email: melcoIdToEmail(melcoId),
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
  }

  static Future<Map<String, dynamic>?> currentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data();
  }

  static Future<bool> currentUserIsAdmin() async {
    final data = await currentUserProfile();
    return data?['role'] == 'admin';
  }

  static Future<bool> currentUserMustChangePassword() async {
    final data = await currentUserProfile();
    return data?['mustChangePassword'] == true || data?['requirePasswordChange'] == true;
  }

  static Future<void> changeCurrentPassword(String newPassword) async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    await user.updatePassword(newPassword);
    await _firestore.collection('users').doc(user.uid).set({
      'mustChangePassword': false,
      'requirePasswordChange': false,
      'lastPasswordChangedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
