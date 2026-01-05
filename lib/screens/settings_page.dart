import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/state_cache.dart';
import '../services/divers_service.dart';

import '../core/constants.dart';
import '../core/departments.dart';
import '../core/utils.dart';
import '../widgets/top_alert.dart';
import '../app.dart';
import 'history_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Box diversBox;
  int currentlyIn = 0;
  Timer? _timer;
  bool darkMode = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _diversSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  List<Map<String, dynamic>> _divers = [];

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    darkMode = Hive.box('prefs').get('darkMode', defaultValue: false);
    _update();
    _loadDivers();
    _diversSub = FirebaseFirestore.instance
        .collection('divers')
        .snapshots()
        .listen((_) => _loadDivers());
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen((_) => _update());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  Future<void> _update() async {
    if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diversSub?.cancel();
    _checkinsSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get divers => _divers;

  Future<void> _loadDivers() async {
    try {
      _divers = await DiversService.getDivers();
    } catch (_) {
      final stored = diversBox.get('diversList', defaultValue: <Map>[]);
      _divers = List<Map>.from(
        stored,
      ).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    _divers.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _showAddDialog() {
    // Use the same full-featured dialog as Edit Diver, but with empty defaults.
    _showDiverDialog(diver: null);
  }

  // (Old remove dialog removed; editing covers name/department updates. Implement removal if needed.)

  void _showEditDiverDialog(Map diver) {
    _showDiverDialog(diver: diver);
  }

  void _showDiverDialog({Map? diver}) {
    final checkinsBox = Hive.box('checkins');
    final bool isEdit = diver != null;
    final String? diverId = isEdit ? (diver!['id']?.toString()) : null;
    String oldName = isEdit ? (diver['name'] ?? '').toString() : '';
    String newName = isEdit ? oldName : '';
    // Persist a single controller instance across dialog rebuilds so the
    // typed name doesn't disappear when other controls trigger setState.
    final TextEditingController nameController = TextEditingController(
      text: isEdit ? newName : '',
    );
    String selectedDepartment = isEdit
        ? (diver['department'] ?? '').toString()
        : (getDepartmentChoicesForAdd().isNotEmpty
              ? getDepartmentChoicesForAdd().first
              : 'SHOW DIVERS');
    if (selectedDepartment.isEmpty) {
      final choices = getDepartmentChoicesForAdd();
      if (choices.isNotEmpty) selectedDepartment = choices.first;
    }
    String? selectedTeam = selectedDepartment == 'SHOW DIVERS'
        ? (isEdit ? (diver['team'] ?? teams.first).toString() : teams.first)
        : null;
    bool gasAir = isEdit ? (diver['gasAir'] ?? false) == true : false;
    bool gasNitrox = isEdit ? (diver['gasNitrox'] ?? false) == true : false;
    bool gffm = isEdit ? (diver['gffm'] ?? false) == true : false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit Diver' : 'Add Diver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Diver Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => newName = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDepartment,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final dep in getDepartmentChoicesForAdd())
                      DropdownMenuItem(value: dep, child: Text(dep)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setDialog(() {
                      selectedDepartment = val;
                      if (selectedDepartment == 'SHOW DIVERS') {
                        selectedTeam ??= teams.first;
                      } else {
                        selectedTeam = null;
                      }
                    });
                  },
                ),
                if (selectedDepartment == 'SHOW DIVERS') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedTeam,
                    decoration: const InputDecoration(
                      labelText: 'Team',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in teams)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (val) => setDialog(() => selectedTeam = val),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Gas:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      selected: gasAir,
                      label: const Text('Air'),
                      selectedColor: Colors.blue[300],
                      onSelected: (v) => setDialog(() {
                        gasAir = v;
                        if (v) gasNitrox = false;
                      }),
                    ),
                    FilterChip(
                      selected: gasNitrox,
                      label: const Text('Nitrox'),
                      selectedColor: Colors.green[400],
                      onSelected: (v) => setDialog(() {
                        gasNitrox = v;
                        if (v) gasAir = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Guardian Full Face Mask:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Switch(
                      value: gffm,
                      onChanged: (v) => setDialog(() => gffm = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: const Text('Remove Diver'),
                      content: Text(
                        "Are you sure you want to remove '$oldName'?",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    // Do not allow removal if diver is currently in water.
                    if (diverId != null && StateCache.diverIsInWater(diverId)) {
                      _snack("Cannot remove diver who is currently IN WATER.");
                      return;
                    }
                    if (diverId != null) {
                      await DiversService.removeDiver(diverId);
                    }
                    // Firestore cascade handles check-ins; remove local legacy entry if present.
                    try {
                      if (diverId != null) checkinsBox.delete(diverId);
                    } catch (_) {}
                    Navigator.pop(ctx);
                    setState(() {});
                    _snack('Diver removed.');
                  }
                },
                child: const Text(
                  'Remove Diver',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newName.trim().isEmpty) {
                  _snack("Name can't be empty.");
                  return;
                }
                // Require at least one gas selection (Air or Nitrox)
                if (!gasAir && !gasNitrox) {
                  _snack("Select gas: Air or Nitrox.");
                  return;
                }
                // Enforce duplicate rules:
                // - Same name within the same department is NOT allowed
                // - For SHOW DIVERS, same name within the same team color is NOT allowed
                // - Same name across different departments (or different team colors in SHOW DIVERS) is allowed
                bool _clash() {
                  final String n = newName.trim().toLowerCase();
                  final String dep = (selectedDepartment).toString();
                  final String depL = dep.toLowerCase();
                  final String teamL = (selectedTeam ?? '')
                      .toString()
                      .toLowerCase();
                  for (final d in _divers) {
                    final String dId = (d['id'] ?? '').toString();
                    if (isEdit && diverId != null && dId == diverId)
                      continue; // ignore self when editing
                    final String dn = (d['name'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    final String dd = (d['department'] ?? '')
                        .toString()
                        .toLowerCase();
                    final String dt = (d['team'] ?? '')
                        .toString()
                        .toLowerCase();
                    if (dn != n) continue;
                    if (depL != 'show divers') {
                      if (dd == depL)
                        return true; // same department + same name
                    } else {
                      if (dd == depL && dt == teamL)
                        return true; // same team color in SHOW DIVERS + same name
                    }
                  }
                  return false;
                }

                if (_clash()) {
                  if (selectedDepartment == 'SHOW DIVERS') {
                    _snack(
                      "A diver named '" +
                          newName.trim() +
                          "' already exists in SHOW DIVERS (team " +
                          (selectedTeam ?? '') +
                          ").",
                    );
                  } else {
                    _snack(
                      "A diver named '" +
                          newName.trim() +
                          "' already exists in " +
                          selectedDepartment +
                          ".",
                    );
                  }
                  return;
                }
                if (isEdit) {
                  // Update diver record
                  if (diverId == null) {
                    _snack('Could not update: missing diver id.');
                    return;
                  }
                  await DiversService.updateDiver(diverId, {
                    'name': newName.trim(),
                    'department': selectedDepartment,
                    'team': selectedDepartment == 'SHOW DIVERS'
                        ? selectedTeam
                        : null,
                    'gasAir': gasAir,
                    'gasNitrox': gasNitrox,
                    'gffm': gffm,
                  });
                  Navigator.pop(ctx);
                  setState(() {});
                  _snack('Diver updated.');
                } else {
                  // Add new diver
                  await DiversService.createDiver({
                    'name': newName.trim(),
                    'department': selectedDepartment,
                    'team': selectedDepartment == 'SHOW DIVERS'
                        ? selectedTeam
                        : null,
                    'gasAir': gasAir,
                    'gasNitrox': gasNitrox,
                    'gffm': gffm,
                  });
                  Navigator.pop(ctx);
                  setState(() {});
                  _snack('Diver added!');
                }
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    final scale = appScale(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('About'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'AQX Dive Log App',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Version: 1.0.0',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text('Updated: 2026-jan-05 at 11:00 AM'),
            SizedBox(height: 10),
            Text('Developed by: Ricardo Costa Silva'),
            SizedBox(height: 6),
            SelectableText('Contact: akosiricardocosta@gmail.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(fontSize: 14 * scale)),
          ),
        ],
      ),
    );
  }

  void _toggleDark(bool value) async {
    MyApp.of(context)?.toggleDarkMode(value);
    setState(() => darkMode = value);
    Hive.box('prefs').put('darkMode', value);
    try {
      await FirebaseFirestore.instance.collection('prefs').doc('app').set({
        'darkMode': value,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _resetCheckIns() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Day Reset"),
        content: const Text(
          "This will clear today's CHECKED‑IN list (not IN WATER).\nDivers currently IN WATER will remain checked‑in and carry over.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reset"),
            onPressed: () async {
              // Clear only those checked‑in who are NOT currently IN WATER
              final coll = FirebaseFirestore.instance.collection('checkins');
              final ids = StateCache.checkedInIds();
              final batch = FirebaseFirestore.instance.batch();
              for (final id in ids) {
                if (!StateCache.diverIsInWater(id)) {
                  batch.delete(coll.doc(id));
                }
              }
              await batch.commit();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Checked‑In list cleared.")),
                );
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final list = divers;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(
            currentlyIn: currentlyIn,
            onTap: () {
              // Quick jump to live IN WATER view in Log
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HistoryPage(selectedColor: "IN WATER"),
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, size: 28 * scale),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(width: 12 * scale),
                    Text(
                      "Settings",
                      style: TextStyle(
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'About',
                      icon: Icon(Icons.info_outline, size: 26 * scale),
                      onPressed: _showAbout,
                    ),
                  ],
                ),
                SizedBox(height: 10 * scale),
                // Top action buttons in one horizontal line, equal widths
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50 * scale,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.add, size: 22 * scale),
                            label: Text(
                              'Add Diver',
                              style: TextStyle(fontSize: 16 * scale),
                            ),
                            onPressed: _showAddDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: SizedBox(
                          height: 50 * scale,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.refresh, size: 22 * scale),
                            label: Text(
                              'New Day Reset (Checked‑In only)',
                              style: TextStyle(fontSize: 16 * scale),
                            ),
                            onPressed: _resetCheckIns,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[600],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: SizedBox(
                          height: 50 * scale,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.history, size: 20 * scale),
                            label: Text(
                              'History of Dives',
                              style: TextStyle(fontSize: 16 * scale),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HistoryPage(
                                  selectedColor: 'ALL',
                                  showTabs: false,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Reset is always allowed; divers currently IN WATER are preserved.
                SizedBox(height: 12 * scale),
                SizedBox(height: 12 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Dark theme",
                      style: TextStyle(
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: darkMode,
                    onChanged: _toggleDark,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              "No divers yet.\nTap 'Add Diver' to get started.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20 * scale,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = list[i];
                              String subtitle = d['department'] ?? '';
                              if (d['department'] == "SHOW DIVERS" &&
                                  d['team'] != null) {
                                subtitle += " - ${d['team']}";
                              }
                              return Container(
                                color: i % 2 == 0
                                    ? Colors.white
                                    : Colors.grey[100],
                                child: ListTile(
                                  title: Text(
                                    d['name'] ?? '',
                                    style: TextStyle(fontSize: 20 * scale),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subtitle,
                                        style: TextStyle(fontSize: 14 * scale),
                                      ),
                                      Builder(
                                        builder: (_) {
                                          final bool gasAir =
                                              (d['gasAir'] ?? false) == true;
                                          final bool gasNitrox =
                                              (d['gasNitrox'] ?? false) == true;
                                          final bool gffm =
                                              (d['gffm'] ?? false) == true;
                                          final chips = <Widget>[];
                                          if (gasAir) {
                                            chips.add(
                                              Chip(
                                                label: const Text('AIR'),
                                                backgroundColor:
                                                    Colors.blue[300],
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (gasNitrox) {
                                            chips.add(
                                              Chip(
                                                label: const Text('NITROX'),
                                                backgroundColor:
                                                    Colors.green[400],
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (gffm) {
                                            chips.add(
                                              Chip(
                                                label: const Text('GFFM'),
                                                backgroundColor: Colors.black87,
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (chips.isEmpty)
                                            return const SizedBox.shrink();
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              top: 4 * scale,
                                            ),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: -6,
                                              children: chips,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.edit,
                                      color: Colors.blueGrey[700],
                                      size: 22 * scale,
                                    ),
                                    onPressed: () => _showEditDiverDialog(d),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
