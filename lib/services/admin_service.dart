import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminService {
  static const String workerBaseUrl =
      'https://thodw-admin-worker.akosiricardocosta.workers.dev';

  static Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No logged-in user.');
    }
    final idToken = await user.getIdToken(true);
    return <String, String>{
      'authorization': 'Bearer $idToken',
      'content-type': 'application/json',
    };
  }

  static Exception _toException(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = data['error']?.toString();
      final detail = data['detail']?.toString();
      return Exception(
        [
          if (error != null && error.isNotEmpty) error,
          if (detail != null && detail.isNotEmpty) detail,
        ].join(' '),
      );
    } catch (_) {
      return Exception('Admin backend request failed (${response.statusCode}).');
    }
  }

  static Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await http.get(
      Uri.parse('$workerBaseUrl$path'),
      headers: await _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$workerBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    return response.body.isEmpty
        ? <String, dynamic>{'ok': true}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> adminHealthCheck() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('No logged-in user.');
    }

    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final data = profile.data();

    return <String, dynamic>{
      'ok': data != null && data['role'] == 'admin' && data['active'] != false,
      'backend': 'firestore-direct',
      'uid': currentUser.uid,
      'melcoId': data?['melcoId']?.toString(),
      'role': data?['role']?.toString(),
    };
  }

  static Future<List<Map<String, dynamic>>> listUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('No logged-in user.');
    }

    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final users = snapshot.docs
        .map((doc) {
          final data = doc.data();
          final email = data['email']?.toString() ?? '';
          final melcoId = data['melcoId']?.toString() ??
              (email.endsWith('@hodw.local')
                  ? email.replaceFirst(
                      RegExp(r'@hodw\.local$', caseSensitive: false),
                      '',
                    )
                  : '');
          final normalizedMelcoId =
              melcoId.isEmpty && email.endsWith('@hodw.local')
              ? email.substring(0, email.length - '@hodw.local'.length)
              : melcoId;
          if (normalizedMelcoId.isEmpty) return null;

          final active = data['active'] != false && data['disabled'] != true;
          final mustChange = data['mustChangePassword'] == true ||
              data['requirePasswordChange'] == true;

          return <String, dynamic>{
            'uid': doc.id,
            'melcoId': normalizedMelcoId,
            'displayName': data['displayName']?.toString() ??
                data['employeeName']?.toString() ??
                normalizedMelcoId,
            'role': data['role']?.toString() == 'admin' ? 'admin' : 'operator',
            'active': active,
            'mustChangePassword': mustChange,
            'requirePasswordChange': mustChange,
            'disabledInAuth': data['disabled'] == true,
            'email': email,
            'createdAt': data['createdAt'],
            'updatedAt': data['updatedAt'],
            'lastPasswordResetAt': data['lastPasswordResetAt'],
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    users.sort((a, b) {
      final nameA = '${a['displayName']} ${a['melcoId']}'.toLowerCase();
      final nameB = '${b['displayName']} ${b['melcoId']}'.toLowerCase();
      return nameA.compareTo(nameB);
    });

    return users;
  }

  static Future<Map<String, dynamic>> createUserByAdmin({
    required String melcoId,
    required String displayName,
    String role = 'operator',
    String? tempPassword,
  }) async {
    return _postJson('/users', <String, dynamic>{
      'melcoId': melcoId.trim(),
      'displayName': displayName.trim(),
      'role': role,
      if (tempPassword != null && tempPassword.trim().isNotEmpty)
        'tempPassword': tempPassword.trim(),
    });
  }

  static Future<void> resetUserPasswordByAdmin({
    required String uid,
    String? tempPassword,
  }) async {
    await _postJson('/users/$uid/reset-password', <String, dynamic>{
      if (tempPassword != null && tempPassword.trim().isNotEmpty)
        'tempPassword': tempPassword.trim(),
    });
  }

  static Future<void> setUserActiveStateByAdmin({
    required String uid,
    required bool active,
  }) async {
    await _postJson('/users/$uid/active', <String, dynamic>{
      'active': active,
    });
  }

  static Future<Map<String, dynamic>> forcePasswordChangeForAllUsers() async {
    return _postJson('/users/force-password-change', const <String, dynamic>{});
  }
}
