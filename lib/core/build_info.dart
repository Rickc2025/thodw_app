/// Build-time metadata injected by CI via --dart-define.
class BuildInfo {
  /// UTC timestamp in ISO8601 (e.g., 2025-11-06T12:34:56Z)
  static const String buildTime = String.fromEnvironment(
    'BUILD_TIME',
    defaultValue: '',
  );

  /// Full git SHA of the workflow build
  static const String gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: '',
  );

  /// 7-character short SHA (if available)
  static String get shortSha => gitSha.isNotEmpty ? gitSha.substring(0, 7) : '';

  /// Returns a friendly local time like "2025-06-11 12:22AM".
  /// If BUILD_TIME is missing or invalid, returns empty string.
  static String prettyUpdatedLocal() {
    if (buildTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(buildTime).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      int hour = dt.hour;
      final min = dt.minute.toString().padLeft(2, '0');
      final isAM = hour < 12;
      final suffix = isAM ? 'AM' : 'PM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final hh = hour.toString();
      return '$y-$mo-$d $hh:$min$suffix';
    } catch (_) {
      return '';
    }
  }
}
