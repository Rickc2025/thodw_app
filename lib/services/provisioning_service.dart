import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ProvisioningResult {
  final String email;
  final String password;
  final String role;
  final String displayName;
  final bool created;
  final bool updated;

  const ProvisioningResult({
    required this.email,
    required this.password,
    required this.role,
    required this.displayName,
    required this.created,
    required this.updated,
  });

  factory ProvisioningResult.fromJson(Map<String, dynamic> json) {
    return ProvisioningResult(
      email: (json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      role: (json['role'] ?? 'operator').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      created: json['created'] == true,
      updated: json['updated'] == true,
    );
  }
}

class ProvisioningService {
  ProvisioningService._();

  static const String workerBaseUrl = String.fromEnvironment(
    'THODW_PROVISIONER_URL',
    defaultValue: '',
  );

  static bool get isConfigured => workerBaseUrl.trim().isNotEmpty;

  static Uri _uri(String path) {
    final base = workerBaseUrl.trim();
    if (base.isEmpty) {
      throw Exception('Provisioning service is not configured yet.');
    }
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.parse('$normalized$path');
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }

    final response = await http.post(
      _uri(path),
      headers: headers,
      body: jsonEncode(payload),
    );

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
      final message =
          (body['error'] ??
                  body['message'] ??
                  'Request failed (${response.statusCode}).')
              .toString();
      throw Exception(message);
    }

    return body;
  }

  static Future<ProvisioningResult> bootstrapAdmin({
    required String melcoId,
    required String displayName,
    String role = 'admin',
    required String bootstrapToken,
  }) async {
    final json = await _postJson('/bootstrap-admin', {
      'melcoId': melcoId,
      'displayName': displayName,
      'role': role,
      'bootstrapToken': bootstrapToken,
    });
    return ProvisioningResult.fromJson(json);
  }

  static Future<ProvisioningResult> createLoginUser({
    required String melcoId,
    required String displayName,
    required String role,
  }) async {
    final json = await _postJson('/users', {
      'melcoId': melcoId,
      'displayName': displayName,
      'role': role,
    });
    return ProvisioningResult.fromJson(json);
  }
}
