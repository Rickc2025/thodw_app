/// Build-time metadata injected by CI via --dart-define.
class BuildInfo {
  /// UTC timestamp in ISO8601 (e.g., 2025-11-06T12:34:56Z)
  static const String buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');
  /// Full git SHA of the workflow build
  static const String gitSha = String.fromEnvironment('GIT_SHA', defaultValue: '');

  /// Returns a friendly local time like "2025-06-11 12:22AM" or an empty string if unknown.
  static String prettyUpdatedLocal() {
    if (buildTime.isEmpty) return '';
    DateTime? dt;
    try {
      dt = DateTime.tryParse(buildTime)?.toLocal();
    } catch (_) {}
    if (dt == null) return '';
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
  }
}
