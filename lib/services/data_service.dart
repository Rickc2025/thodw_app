import 'package:hive/hive.dart';

// Logs/Checkins helpers backed by Hive

Future<int> getCurrentlyInCount() async {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  final List<Map> logsList = List<Map>.from(logs);
  final Map<String, Map> lastLogByDiverTag = {};
  for (final log in logsList.reversed) {
    final key = "${log['name'] ?? ''}|${log['tag'] ?? ''}";
    if (!lastLogByDiverTag.containsKey(key)) {
      lastLogByDiverTag[key] = log;
    }
  }
  return lastLogByDiverTag.values
      .where((l) => (l['status'] ?? '') == 'IN')
      .length;
}

bool diverIsInWater(String name) {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  final list = List<Map>.from(logs);
  final diverLogs = list.where((l) => l['name'] == name).toList();
  if (diverLogs.isEmpty) return false;
  return diverLogs.last['status'] == 'IN';
}

int? lastInTank(String name) {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  for (final log in List<Map>.from(logs).reversed) {
    if (log['name'] == name && log['status'] == 'IN') return log['tag'];
  }
  return null;
}

bool isCheckedIn(String name) {
  final box = Hive.box('checkins');
  final data = (box.get(name) ?? {}) as Map;
  return (data['checkedIn'] ?? false) == true;
}

int? checkedInTank(String name) {
  final box = Hive.box('checkins');
  final data = (box.get(name) ?? {}) as Map;
  if (data.isEmpty) return null;
  return data['tag'] is int ? data['tag'] : int.tryParse("${data['tag']}");
}

bool tankInUse(int tag, {String? exceptName}) {
  final box = Hive.box('checkins');
  for (final key in box.keys) {
    if (key == exceptName) continue;
    final data = (box.get(key) ?? {}) as Map;
    if ((data['checkedIn'] ?? false) == true) {
      final t = data['tag'];
      final val = t is int ? t : int.tryParse("$t");
      if (val == tag) return true;
    }
  }
  return false;
}
