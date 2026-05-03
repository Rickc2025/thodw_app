import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String bootstrapAdminMelcoId = '1015083';
  static const String bootstrapAdminPassword = 'Welcome2026';

  static String melcoIdToEmail(String melcoId) => '${melcoId.trim()}@thodw.local';

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

  static Future<void> ensureBootstrapAdminExists() async {
    final usersRef = _firestore.collection('users');
    final existing = await usersRef.where('melcoId', isEqualTo: bootstrapAdminMelcoId).limit(1).get();
    if (existing.docs.isNotEmpty) return;

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: melcoIdToEmail(bootstrapAdminMelcoId),
        password: bootstrapAdminPassword,
      );

      await usersRef.doc(cred.user!.uid).set({
        'melcoId': bootstrapAdminMelcoId,
        'displayName': 'Ricardo Costa Silva',
        'role': 'admin',
        'active': true,
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'bootstrap',
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      final snap = await usersRef.where('melcoId', isEqualTo: bootstrapAdminMelcoId).limit(1).get();
      if (snap.docs.isEmpty) rethrow;
    }
  }

  static Future<UserCredential> signInWithMelcoId({required String melcoId, required String password}) {
    return _auth.signInWithEmailAndPassword(
      email: melcoIdToEmail(melcoId),
      password: password,
    );
  }

  static Future<void> signOut() => _auth.signOut();

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
    return data?['mustChangePassword'] == true;
  }

  static Future<void> changeCurrentPassword(String newPassword) async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    await user.updatePassword(newPassword);
    await _firestore.collection('users').doc(user.uid).set({
      'mustChangePassword': false,
      'lastPasswordChangedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
