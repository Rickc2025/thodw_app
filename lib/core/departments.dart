import 'package:hive/hive.dart';
import 'constants.dart';

/// Reserved core departments that are handled specially in the UI.
const String kShowDivers = "SHOW DIVERS";
const String kDayCrew = "DAY CREW";
const String kOther = "OTHER";

List<String> getCustomDepartments() {
  final box = Hive.box('prefs');
  final list = box.get('customDepartments', defaultValue: <String>[]) as List;
  return List<String>.from(list.map((e) => e.toString()));
}

void saveCustomDepartments(List<String> items) {
  final box = Hive.box('prefs');
  final unique =
      <String>{for (final s in items) s.trim()}
          .where(
            (s) =>
                s.isNotEmpty &&
                s.toUpperCase() != kShowDivers &&
                s.toUpperCase() != kDayCrew,
          )
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  box.put('customDepartments', unique);
}

void addCustomDepartment(String name) {
  final list = getCustomDepartments();
  final n = name.trim();
  if (n.isEmpty) return;
  // Prevent adding duplicates of built-ins (including OTHER)
  final upper = n.toUpperCase();
  if (upper == kShowDivers || upper == kDayCrew) return;
  final builtIn = departments.map((e) => e.toUpperCase()).toSet();
  if (builtIn.contains(upper)) return;
  if (!list.any((e) => e.toLowerCase() == n.toLowerCase())) {
    list.add(n);
    saveCustomDepartments(list);
  }
}

void removeCustomDepartment(String name) {
  final list = getCustomDepartments();
  list.removeWhere((e) => e.toLowerCase() == name.toLowerCase());
  saveCustomDepartments(list);
}

// --- Permanent removal of built-in (non-core) departments ---
// We persist a list of removed base departments; deleting also clears assignments from divers.

List<String> getRemovedBaseDepartments() {
  final box = Hive.box('prefs');
  final list =
      box.get('removedBaseDepartments', defaultValue: <String>[]) as List;
  return List<String>.from(list.map((e) => e.toString()));
}

void saveRemovedBaseDepartments(List<String> items) {
  final box = Hive.box('prefs');
  final clean =
      <String>{for (final s in items) s.trim()}
          .where(
            (s) =>
                s.isNotEmpty &&
                s.toUpperCase() != kShowDivers &&
                s.toUpperCase() != kDayCrew,
          )
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  box.put('removedBaseDepartments', clean);
}

bool permanentlyRemoveBaseDepartment(String name) {
  final n = name.trim();
  if (n.isEmpty) return false;
  final u = n.toUpperCase();
  if (u == kShowDivers || u == kDayCrew) return false; // protect core
  // Must be a built-in department (including OTHER) and not custom
  final builtIn = departments
      .where((d) => d != kShowDivers && d != kDayCrew)
      .map((e) => e.toUpperCase())
      .toSet();
  if (!builtIn.contains(u)) return false;
  // Block deletion if any divers are assigned to this department
  final diversBox = Hive.box('divers');
  final stored = diversBox.get('diversList', defaultValue: <Map>[]) as List;
  final list = List<Map>.from(stored);
  final hasAssigned = list.any(
    (d) => (d['department'] ?? '').toString().toLowerCase() == n.toLowerCase(),
  );
  if (hasAssigned) return false;
  final removed = getRemovedBaseDepartments();
  if (!removed.any((e) => e.toLowerCase() == n.toLowerCase())) {
    removed.add(n);
    saveRemovedBaseDepartments(removed);
  }
  return true;
}

List<String> activeBaseDepartments() {
  final removed = getRemovedBaseDepartments()
      .map((e) => e.toLowerCase())
      .toSet();
  final base = <String>[
    for (final d in departments)
      if (d != kShowDivers && d != kDayCrew) d,
  ];
  final filtered = [
    for (final d in base)
      if (!removed.contains(d.toLowerCase())) d,
  ];
  filtered.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return filtered;
}

// Department choices for Add Diver dropdown: SHOW DIVERS, DAY CREW, active base, then custom
List<String> getDepartmentChoicesForAdd() {
  final List<String> choices = [kShowDivers, kDayCrew];
  choices.addAll(activeBaseDepartments());
  choices.addAll(getCustomDepartments());
  // Ensure unique while preserving order
  final seen = <String>{};
  final deduped = <String>[];
  for (final d in choices) {
    final key = d.toLowerCase();
    if (!seen.contains(key)) {
      seen.add(key);
      deduped.add(d);
    }
  }
  return deduped;
}
