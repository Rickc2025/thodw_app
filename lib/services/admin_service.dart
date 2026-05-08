import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminManagedUser {
  final String uid;
  final String melcoId;
  final String role;
  final String displayName;
  final String email;
  final bool requirePasswordChange;
  final bool disabled;
  final bool bootstrapAdmin;

  const AdminManagedUser({
    required this.uid,
    required this.melcoId,
    required this.role,
    required this.displayName,
    required this.email,
    required this.requirePasswordChange,
    required this.disabled,
    required this.bootstrapAdmin,
  });

  factory AdminManagedUser.fromJson(Map<String, dynamic> json) {
    return AdminManagedUser(
      uid: (json['uid'] ?? '').toString(),
      melcoId: (json['melcoId'] ?? '').toString(),
      role: (json['role'] ?? 'operator').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      requirePasswordChange: json['requirePasswordChange'] == true,
      disabled: json['disabled'] == true,
      bootstrapAdmin: json['bootstrapAdmin'] == true,
    );
  }
}

class PasswordResetResult {
  final String uid;
  final String melcoId;
  final String displayName;
  final String email;
  final String password;

  const PasswordResetResult({
    required this.uid,
    required this.melcoId,
    required this.displayName,
    required this.email,
    required this.password,
  });

  factory PasswordResetResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetResult(
      uid: (json['uid'] ?? '').toString(),
      melcoId: (json['melcoId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }
}

class AdminService {
  AdminService._();

  static const String workerBaseUrl = String.fromEnvironment(
    'THODW_PROVISIONER_URL',
    defaultValue: '',
  );

  static bool get isConfigured => workerBaseUrl.trim().isNotEmpty;

  static Uri _uri(String path) {
    final base = workerBaseUrl.trim();
    if (base.isEmpty) {
      throw Exception('Admin service is not configured yet.');
    }
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.parse('$normalized$path');
  }

  static Future<Map<String, String>> _headers() async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception('You must be logged in as an admin.');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
  }

  static Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {}
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (body['error'] ?? body['message'] ?? 'Request failed.')
          .toString();
      throw Exception(message);
    }
    return body;
  }

  static Future<List<AdminManagedUser>> listUsers() async {
    final response = await http.get(_uri('/users'), headers: await _headers());
    final body = await _decode(response);
    final users = (body['users'] as List?) ?? const [];
    return users
        .whereType<Map>()
        .map((e) => AdminManagedUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<PasswordResetResult> resetPassword(String uid) async {
    final response = await http.post(
      _uri('/users/reset-password'),
      headers: await _headers(),
      body: jsonEncode({'uid': uid}),
    );
    final body = await _decode(response);
    return PasswordResetResult.fromJson(body);
  }

  static Future<void> setDisabled({
    required String uid,
    required bool disabled,
  }) async {
    final response = await http.post(
      _uri('/users/set-disabled'),
      headers: await _headers(),
      body: jsonEncode({'uid': uid, 'disabled': disabled}),
    );
    await _decode(response);
  }
}
