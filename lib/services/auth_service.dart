import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppUserProfile {
  final String uid;
  final String melcoId;
  final String role;
  final bool requirePasswordChange;
  final String? displayName;

  const AppUserProfile({
    required this.uid,
    required this.melcoId,
    required this.role,
    required this.requirePasswordChange,
    this.displayName,
  });

  bool get isAdmin => role == 'admin';
  bool get isOperator => role == 'operator';

  factory AppUserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUserProfile(
      uid: doc.id,
      melcoId: (data['melcoId'] ?? '').toString(),
      role: ((data['role'] ?? 'operator').toString()).toLowerCase(),
      requirePasswordChange: data['requirePasswordChange'] == true,
      displayName: data['displayName']?.toString(),
    );
  }
}

class AuthService {
  AuthService._();

  static const String melcoDomain = '@hodw.local';
  static const String bootstrapAdminMelcoId = '1015083';

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  static String melcoIdToEmail(String melcoId) => '$melcoId$melcoDomain';

  static String normalizeMelcoId(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits;
  }

  static bool isMelcoIdValid(String raw) => normalizeMelcoId(raw).isNotEmpty;

  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  static Stream<AppUserProfile?> profileStream(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUserProfile.fromDoc(doc);
    });
  }

  static Future<AppUserProfile?> getProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUserProfile.fromDoc(doc);
  }

  static Future<AppUserProfile> signInWithMelcoId({
    required String melcoId,
    required String password,
  }) async {
    final normalizedMelcoId = normalizeMelcoId(melcoId);
    if (normalizedMelcoId.isEmpty) {
      throw Exception('Enter a valid Melco ID.');
    }

    final credential = await _auth.signInWithEmailAndPassword(
      email: melcoIdToEmail(normalizedMelcoId),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Login failed. Please try again.');
    }
    if (user.isAnonymous) {
      await _auth.signOut();
      throw Exception('Anonymous access is not allowed. Please log in.');
    }

    var profile = await getProfile(user.uid);

    if (profile == null && normalizedMelcoId == bootstrapAdminMelcoId) {
      await _users.doc(user.uid).set({
        'melcoId': normalizedMelcoId,
        'role': 'admin',
        'requirePasswordChange': true,
        'displayName': 'Ricardo',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'bootstrapAdmin': true,
      }, SetOptions(merge: true));
      profile = await getProfile(user.uid);
    }

    if (profile == null) {
      await _auth.signOut();
      throw Exception(
        'Your account is not provisioned yet. Ask an admin to create your users profile.',
      );
    }

    if (profile.melcoId.isNotEmpty && profile.melcoId != normalizedMelcoId) {
      await _auth.signOut();
      throw Exception('This account is mapped to a different Melco ID.');
    }

    return profile;
  }

  static Future<void> changePassword({required String newPassword}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('You must be logged in to change password.');
    }
    if (newPassword.trim().length < 6) {
      throw Exception('Password must be at least 6 characters.');
    }

    await user.updatePassword(newPassword.trim());
    await _users.doc(user.uid).set({
      'requirePasswordChange': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signOut() => _auth.signOut();
}
