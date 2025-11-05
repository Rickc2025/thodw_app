import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
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
    String selectedDepartment = departments.first;
    String? selectedTeam = teams.first;
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
                  for (final dep in departments)
                    DropdownMenuItem(value: dep, child: Text(dep)),
                ],
                onChanged: (val) {
                  setStateDialog(() {
                    selectedDepartment = val!;
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

  void _confirmRemove(String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove Diver"),
        content: Text("Are you sure you want to remove '$name' ?"),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text('Remove'),
            onPressed: () {
              final arr = diversBox.get('diversList', defaultValue: <Map>[]);
              final list = List<Map>.from(arr);
              list.removeWhere((d) => d['name'] == name);
              diversBox.put('diversList', list);
              Navigator.pop(context);
              setState(() {});
              _snack("Diver removed.");
            },
          ),
        ],
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
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.add, size: 24 * scale),
                    label: Text(
                      'Add Diver',
                      style: TextStyle(fontSize: 20 * scale),
                    ),
                    onPressed: _showAddDialog,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(50 * scale),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16 * scale),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.refresh, size: 24 * scale),
                    label: Text(
                      'New Day Reset (Checked‑In only)',
                      style: TextStyle(fontSize: 18 * scale),
                    ),
                    onPressed: currentlyIn > 0 ? null : _resetCheckIns,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(48 * scale),
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
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
                // History of Dives (full, no tabs)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.history, size: 22 * scale),
                    label: Text(
                      'History of Dives',
                      style: TextStyle(fontSize: 18 * scale),
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
                      minimumSize: Size.fromHeight(48 * scale),
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16 * scale),
                      ),
                    ),
                  ),
                ),
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
                                subtitle: Text(
                                  subtitle,
                                  style: TextStyle(fontSize: 14 * scale),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 22 * scale,
                                  ),
                                  onPressed: () => _confirmRemove(d['name']),
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
