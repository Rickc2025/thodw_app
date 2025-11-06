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
    String newName = '';
    String selectedDepartment = getDepartmentChoicesForAdd().first;
    String? selectedTeam = teams.first;
    const manageSentinel = '__MANAGE_DEPARTMENTS__';

    List<String> _departmentChoices() => getDepartmentChoicesForAdd();

    Future<void> _openManageDepartments(
      BuildContext ctx,
      void Function(void Function()) setStateDialog,
    ) async {
      final controller = TextEditingController();
      await showDialog(
        context: ctx,
        builder: (_) {
          return StatefulBuilder(
            builder: (c, setStateManage) {
              final custom = getCustomDepartments();
              final removableBuiltIns = [
                for (final d in departments)
                  if (d != 'SHOW DIVERS' && d != 'DAY CREW') d,
              ];
              return AlertDialog(
                title: const Text('Manage Departments'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Add new department',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        final n = controller.text.trim();
                        if (n.isEmpty) return;
                        addCustomDepartment(n);
                        controller.clear();
                        setStateManage(() {});
                        setStateDialog(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Built-in departments (delete permanently):',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 360,
                      height: 200,
                      child: ListView.separated(
                        itemCount: removableBuiltIns.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final dep = removableBuiltIns[i];
                          final stored = Hive.box(
                            'divers',
                          ).get('diversList', defaultValue: <Map>[]);
                          final diverList = List<Map>.from(stored);
                          final assignedCount = diverList
                              .where((d) => (d['department'] ?? '') == dep)
                              .length;
                          final hasAssigned = assignedCount > 0;
                          return ListTile(
                            title: Text(dep),
                            subtitle: hasAssigned
                                ? Text(
                                    '$assignedCount assigned • Remove or reassign divers first.',
                                  )
                                : const Text('No divers assigned'),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_forever,
                                color: hasAssigned ? Colors.grey : Colors.red,
                              ),
                              onPressed: hasAssigned
                                  ? null
                                  : () async {
                                      final ok = await showDialog<bool>(
                                        context: c,
                                        builder: (dlgCtx) => AlertDialog(
                                          title: const Text(
                                            'Delete Department',
                                          ),
                                          content: Text(
                                            "Delete '$dep'? This will remove it from choices.",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dlgCtx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(dlgCtx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        final success =
                                            permanentlyRemoveBaseDepartment(
                                              dep,
                                            );
                                        if (success) {
                                          setStateManage(() {});
                                          setStateDialog(() {});
                                        }
                                      }
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (custom.isEmpty)
                      const Text('No custom departments yet.')
                    else
                      SizedBox(
                        width: 360,
                        height: 220,
                        child: ListView.separated(
                          itemCount: custom.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => ListTile(
                            title: Text(custom[i]),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                removeCustomDepartment(custom[i]);
                                setStateManage(() {});
                                setStateDialog(() {});
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final n = controller.text.trim();
                      if (n.isNotEmpty) {
                        addCustomDepartment(n);
                        controller.clear();
                        setStateManage(() {});
                        setStateDialog(() {});
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Add Diver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Diver Name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => newName = v,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final dep in _departmentChoices())
                    DropdownMenuItem(value: dep, child: Text(dep)),
                  const DropdownMenuItem(
                    value: manageSentinel,
                    child: Text('Manage departments…'),
                  ),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  if (val == manageSentinel) {
                    await _openManageDepartments(context, setStateDialog);
                    // Keep current selection or reset to first available
                    final choices = _departmentChoices();
                    if (!choices.contains(selectedDepartment)) {
                      selectedDepartment = choices.first;
                    }
                    setStateDialog(() {});
                    return;
                  }
                  setStateDialog(() {
                    selectedDepartment = val;
                    if (selectedDepartment == "SHOW DIVERS") {
                      selectedTeam ??= teams.first;
                    } else {
                      selectedTeam = null;
                    }
                  });
                },
              ),
              if (selectedDepartment == "SHOW DIVERS") ...[
                const SizedBox(height: 14),
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
                  onChanged: (val) => setStateDialog(() => selectedTeam = val),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                if (newName.trim().isEmpty) {
                  _snack("Diver name can't be empty.");
                  return;
                }
                final arr = diversBox.get('diversList', defaultValue: <Map>[]);
                if (List<Map>.from(arr).any(
                  (d) =>
                      (d['name'] ?? '').toLowerCase() ==
                      newName.trim().toLowerCase(),
                )) {
                  _snack("Diver already exists.");
                  return;
                }
                final list = List<Map>.from(arr);
                list.add({
                  'name': newName.trim(),
                  'department': selectedDepartment,
                  'team': selectedTeam,
                });
                diversBox.put('diversList', list);
                Navigator.pop(ctx);
                setState(() {});
                _snack("Diver added!");
              },
            ),
          ],
        ),
      ),
    );
  }

  // (Old remove dialog removed; editing covers name/department updates. Implement removal if needed.)

  void _showEditDiverDialog(Map diver) {
    final checkinsBox = Hive.box('checkins');
    String oldName = (diver['name'] ?? '').toString();
    String newName = oldName;
    String selectedDepartment = (diver['department'] ?? '').toString();
    if (selectedDepartment.isEmpty) {
      final choices = getDepartmentChoicesForAdd();
      if (choices.isNotEmpty) selectedDepartment = choices.first;
    }
    String? selectedTeam = selectedDepartment == 'SHOW DIVERS'
        ? ((diver['team'] ?? teams.first).toString())
        : null;
    bool gasAir = (diver['gasAir'] ?? false) == true;
    bool gasNitrox = (diver['gasNitrox'] ?? false) == true;
    bool gffm = (diver['gffm'] ?? false) == true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Edit Diver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: TextEditingController(text: newName),
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
                        if (v) gasNitrox = false; // enforce mutual exclusivity
                      }),
                    ),
                    FilterChip(
                      selected: gasNitrox,
                      label: const Text('Nitrox'),
                      selectedColor: Colors.green[400],
                      onSelected: (v) => setDialog(() {
                        gasNitrox = v;
                        if (v) gasAir = false; // enforce mutual exclusivity
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'GFFM:',
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
                  // Also clear any check-in entry for this diver
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
                final arr = diversBox.get('diversList', defaultValue: <Map>[]);
                final list = List<Map>.from(arr);
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
              },
              child: const Text('Save'),
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
