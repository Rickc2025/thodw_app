import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminService {
  // Canonical production admin backend for THODW is the Cloudflare Worker.
  static const String workerBaseUrl =
      'https://thodw-auth-provisioner.aqxdivelog.workers.dev';

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
        [if (error != null && error.isNotEmpty) error, if (detail != null && detail.isNotEmpty) detail]
            .join(' '),
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
    return _getJson('/admin/check');
  }

  static Future<List<Map<String, dynamic>>> listUsers() async {
    final data = await _getJson('/users');
    return ((data['users'] as List?) ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
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
