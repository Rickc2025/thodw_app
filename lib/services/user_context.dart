class UserContext {
  static String? melcoId;
  static String? role;
  static String? displayName;

  static bool get isAdmin => role == 'admin';

  static void clear() {
    melcoId = null;
    role = null;
    displayName = null;
  }
}
