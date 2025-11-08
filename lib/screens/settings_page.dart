import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../core/departments.dart';
import '../core/utils.dart';
import '../services/data_service.dart';
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

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    darkMode = Hive.box('prefs').get('darkMode', defaultValue: false);
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  Future<void> _update() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Map> get divers {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    list.sort(
      (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
        (b['name'] ?? '').toLowerCase(),
      ),
    );
    return list;
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
    String oldName = isEdit ? (diver['name'] ?? '').toString() : '';
    String newName = isEdit ? oldName : '';
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
                  controller: TextEditingController(
                    text: isEdit ? newName : null,
                  ),
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
                    final arr = diversBox.get(
                      'diversList',
                      defaultValue: <Map>[],
                    );
                    final list = List<Map>.from(arr);
                    list.removeWhere((d) => (d['name'] ?? '') == oldName);
                    diversBox.put('diversList', list);
                    checkinsBox.delete(oldName);
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
              onPressed: () {
                if (newName.trim().isEmpty) {
                  _snack("Name can't be empty.");
                  return;
                }
                // Require at least one gas selection (Air or Nitrox)
                if (!gasAir && !gasNitrox) {
                  _snack("Select gas: Air or Nitrox.");
                  return;
                }
                final arr = diversBox.get('diversList', defaultValue: <Map>[]);
                final list = List<Map>.from(arr);
                if (isEdit) {
                  // Check duplicate name (excluding current diver)
                  if (list.any(
                    (d) =>
                        (d['name'] ?? '').toString().toLowerCase() ==
                            newName.trim().toLowerCase() &&
                        (d['name'] ?? '') != oldName,
                  )) {
                    _snack('Another diver already has this name.');
                    return;
                  }
                  // Update diver record
                  for (int i = 0; i < list.length; i++) {
                    if ((list[i]['name'] ?? '') == oldName) {
                      list[i] = {
                        'name': newName.trim(),
                        'department': selectedDepartment,
                        'team': selectedDepartment == 'SHOW DIVERS'
                            ? selectedTeam
                            : null,
                        'gasAir': gasAir,
                        'gasNitrox': gasNitrox,
                        'gffm': gffm,
                      };
                      break;
                    }
                  }
                  diversBox.put('diversList', list);
                  // Migrate check-in key if name changed
                  if (oldName != newName.trim()) {
                    final data = checkinsBox.get(oldName);
                    if (data != null) {
                      checkinsBox.put(newName.trim(), data);
                      checkinsBox.delete(oldName);
                    }
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                  _snack('Diver updated.');
                } else {
                  // Add new diver
                  if (list.any(
                    (d) =>
                        (d['name'] ?? '').toString().toLowerCase() ==
                        newName.trim().toLowerCase(),
                  )) {
                    _snack('Diver already exists.');
                    return;
                  }
                  list.add({
                    'name': newName.trim(),
                    'department': selectedDepartment,
                    'team': selectedDepartment == 'SHOW DIVERS'
                        ? selectedTeam
                        : null,
                    'gasAir': gasAir,
                    'gasNitrox': gasNitrox,
                    'gffm': gffm,
                  });
                  diversBox.put('diversList', list);
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

  void _toggleDark(bool value) {
    MyApp.of(context)?.toggleDarkMode(value);
    setState(() => darkMode = value);
  }

  void _resetCheckIns() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Day Reset"),
        content: const Text(
          "This will clear today's CHECKED‑IN list.\nWater IN/OUT logs will NOT be affected.",
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
              await Hive.box('checkins').clear();
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
                            onPressed: currentlyIn > 0 ? null : _resetCheckIns,
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
                if (currentlyIn > 0)
                  Padding(
                    padding: EdgeInsets.only(top: 6 * scale),
                    child: Text(
                      'Reset is blocked while any diver is IN.',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                              return ListTile(
                                title: Text(
                                  d['name'] ?? '',
                                  style: TextStyle(fontSize: 20 * scale),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                              backgroundColor: Colors.blue[300],
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
