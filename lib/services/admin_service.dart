class AdminService {
  // Canonical production admin backend for THODW is the Cloudflare Worker,
  // not Firebase callable functions.
  static const String workerBaseUrl =
      'https://thodw-auth-provisioner.aqxdivelog.workers.dev';

  static Never _notWired(String action) {
    throw UnsupportedError(
      'THODW admin action "$action" must go through the Cloudflare Worker backend at $workerBaseUrl. '
      'This local client adapter is intentionally compile-safe until the admin UI is fully reconnected.',
    );
  }

  static Future<void> createUserByAdmin({
    required String melcoId,
    required String displayName,
    String role = 'operator',
    String? tempPassword,
  }) async {
    _notWired('createUserByAdmin');
  }

  static Future<void> resetUserPasswordByAdmin({
    required String uid,
    String? tempPassword,
  }) async {
    _notWired('resetUserPasswordByAdmin');
  }

  static Future<void> setUserActiveStateByAdmin({
    required String uid,
    required bool active,
  }) async {
    _notWired('setUserActiveStateByAdmin');
  }

  static Future<void> forcePasswordChangeForAllUsers() async {
    _notWired('forcePasswordChangeForAllUsers');
  }

  static Future<Map<String, dynamic>> adminHealthCheck() async {
    return <String, dynamic>{
      'backend': 'cloudflare-worker',
      'workerBaseUrl': workerBaseUrl,
    };
  }
}
