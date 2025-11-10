import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'history_page.dart';

class OperatorScreen extends StatefulWidget {
  final String department;
  final String aquacoulisse;
  const OperatorScreen({
    super.key,
    required this.department,
    required this.aquacoulisse,
  });

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  late Box diversBox;
  late Box logsBox;
  late Box checkinsBox;
  List<Map> divers = []; // SHOW DIVERS roster
  String selectedTeam = teams.first;

  // When a non-Show-Divers department is selected, this is set.
  String? selectedDepartmentFilter;

  final Set<String> selectedDivers = {}; // diver names (any department)
  // Optional gas values per selected diver (bars). In: default 200 for OUT divers, Out: default null ('-').
  final Map<String, int?> _gasIn = {}; // 0..250 or null
  final Map<String, int?> _gasOut = {}; // 0..250 or null
  int currentlyIn = 0;
  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    logsBox = Hive.box('logs');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    divers = list.where((d) => d['department'] == "SHOW DIVERS").toList();
    setState(() {});
  }

  Future<void> _tick() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // TEAMS that have at least one checked-in diver (for SHOW DIVERS only)
  List<String> get teamsWithCheckins {
    final Set<String> teamsSet = {};
    for (final key in checkinsBox.keys) {
      final data = (checkinsBox.get(key) ?? {}) as Map;
      if ((data['checkedIn'] ?? false) == true) {
        final list = List<Map>.from(
          diversBox.get('diversList', defaultValue: <Map>[]),
        );
        final match = list.firstWhere(
          (d) => (d['name'] ?? '') == key,
          orElse: () => {},
        );
        if ((match['department'] ?? '') == "SHOW DIVERS") {
          final t = (match['team'] ?? '').toString().toUpperCase();
          if (t.isNotEmpty) teamsSet.add(t);
        }
      }
    }
    return [
      for (final t in teams)
        if (teamsSet.contains(t)) t,
    ];
  }

  List<Map> get checkedInDiversForTeam {
    final available = teamsWithCheckins;
    final useTeam = available.contains(selectedTeam)
        ? selectedTeam
        : (available.isNotEmpty ? available.first : selectedTeam);

    final teamDivers = divers.where((d) => (d['team'] ?? '') == useTeam);
    return teamDivers.where((d) => isCheckedIn(d['name'])).toList();
  }

  String? _departmentForName(String name) {
    final list = List<Map>.from(
      diversBox.get('diversList', defaultValue: <Map>[]),
    );
    for (final d in list) {
      if ((d['name'] ?? '') == name) return d['department'];
    }
    return null;
  }

  List<String> get nonShowDepartmentsWithCheckins {
    final box = checkinsBox;
    final Set<String> depts = {};
    for (final key in box.keys) {
      final data = (box.get(key) ?? {}) as Map;
      if ((data['checkedIn'] ?? false) == true) {
        final dept = _departmentForName(key as String);
        if (dept != null && dept != "SHOW DIVERS") {
          depts.add(dept);
        }
      }
    }
    final ordered = [
      for (final dep in departments)
        if (depts.contains(dep) && dep != "SHOW DIVERS") dep,
    ];
    return ordered;
  }

  List<String> get checkedInNamesForSelectedDepartment {
    if (selectedDepartmentFilter == null) return [];
    final list = List<Map>.from(
      diversBox.get('diversList', defaultValue: <Map>[]),
    );
    final deptNames = list
        .where((d) => d['department'] == selectedDepartmentFilter)
        .map((d) => (d['name'] ?? '').toString())
        .where((n) => n.isNotEmpty && isCheckedIn(n))
        .toList();
    deptNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return deptNames;
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildSelectedPanel(bool isPhone, double scale) {
    // in/out button sizes are computed inside the selected panel helper now
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Selected (${selectedDivers.length})",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: (isPhone ? 20 : 22) * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8 * scale),
        Expanded(
          child: selectedDivers.isEmpty
              ? Center(
                  child: Text(
                    "Tap names to select.\nYou can switch teams/departments; selection stays.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 8 * scale,
                      horizontalMargin: 6 * scale,
                      headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      columns: const [
                        DataColumn(label: Text('Name:')),
                        DataColumn(label: Text('Tank#:')),
                        DataColumn(label: Text('Gas In:')),
                        DataColumn(label: Text('Gas Out:')),
                        DataColumn(label: Text('Status:')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final name in selectedDivers.toList())
                          DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 46,
                                  child: Text(
                                    checkedInTank(
                                          name,
                                        )?.toString().padLeft(2, '0') ??
                                        '--',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 64,
                                  child: InkWell(
                                    onTap: () async {
                                      final v = await _editGas(
                                        context,
                                        initial: _gasIn[name],
                                        title: 'Gas In (bar)',
                                      );
                                      setState(() => _gasIn[name] = v);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6.0,
                                      ),
                                      child: Text(
                                        _gasIn[name] == null
                                            ? '-'
                                            : '${_gasIn[name]}bar',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 64,
                                  child: InkWell(
                                    onTap: () async {
                                      final v = await _editGas(
                                        context,
                                        initial: _gasOut[name],
                                        title: 'Gas Out (bar)',
                                      );
                                      setState(() => _gasOut[name] = v);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6.0,
                                      ),
                                      child: Text(
                                        _gasOut[name] == null
                                            ? '? bar'
                                            : '${_gasOut[name]}bar',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    diverIsInWater(name) ? 'In' : 'Out',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 28,
                                  child: Center(
                                    child: InkWell(
                                      onTap: () => _toggleSelect(name),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        if (mixedSelection)
          Padding(
            padding: EdgeInsets.only(bottom: 8 * scale),
            child: Text(
              "Selection includes both IN and OUT divers.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.orange[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: (isPhone ? 140 : 180) * scale,
              height: (isPhone ? 56 : 68) * scale,
              child: ElevatedButton(
                onPressed: allSelectedAreOut ? _batchIn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36 * scale),
                  ),
                  textStyle: TextStyle(
                    fontSize: (isPhone ? 20 : 22) * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text("IN"),
              ),
            ),
            SizedBox(width: 26 * scale),
            SizedBox(
              width: (isPhone ? 140 : 180) * scale,
              height: (isPhone ? 56 : 68) * scale,
              child: ElevatedButton(
                onPressed: allSelectedAreIn ? _batchOut : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36 * scale),
                  ),
                  textStyle: TextStyle(
                    fontSize: (isPhone ? 20 : 22) * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text("OUT"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Selection state helpers
  bool get allSelectedAreIn =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((n) => diverIsInWater(n));
  bool get allSelectedAreOut =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((n) => !diverIsInWater(n));
  bool get mixedSelection =>
      selectedDivers.isNotEmpty && !(allSelectedAreIn || allSelectedAreOut);

  void _toggleSelect(String name) {
    setState(() {
      if (selectedDivers.contains(name)) {
        selectedDivers.remove(name);
      } else {
        selectedDivers.add(name);
        _gasIn.putIfAbsent(name, () => 200); // default
        _gasOut.putIfAbsent(name, () => null); // unknown by default -> '? bar'
      }
    });
  }

  Future<int?> _editGas(
    BuildContext context, {
    int? initial,
    required String title,
  }) async {
    final controller = TextEditingController(
      text: initial == null ? '' : initial.toString(),
    );
    // Preserve the original value unless the user explicitly saves a change.
    int? result = initial;
    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '0 - 250 bar'),
            maxLength: 3,
          ),
          actions: [
            TextButton(
              // Cancel -> keep existing value (do not clear to '-')
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = controller.text.trim();
                if (txt.isEmpty) {
                  result = null;
                } else {
                  final val = int.tryParse(txt);
                  if (val != null && val >= 0 && val <= 250) {
                    result = val;
                  } else {
                    result = null; // invalid -> treat as null
                  }
                }
                Navigator.pop(dialogCtx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _playConfirm() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/confirm.mp3'));
    } catch (_) {}
  }

  Future<void> _batchIn() async {
    if (!allSelectedAreOut) return;
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    for (final name in selectedDivers) {
      final tag = checkedInTank(name);
      logs.add({
        'name': name,
        'status': 'IN',
        'tag': tag ?? '',
        'datetime': DateTime.now().toIso8601String(),
        'aquacoulisse': widget.aquacoulisse,
        'gasIn': _gasIn[name],
      });
    }
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Checked IN ${selectedDivers.length} diver(s).");
    setState(() => selectedDivers.clear());
  }

  Future<void> _batchOut() async {
    if (!allSelectedAreIn) return;
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    for (final name in selectedDivers) {
      final lt = lastInTank(name);
      logs.add({
        'name': name,
        'status': 'OUT',
        'tag': lt ?? '',
        'datetime': DateTime.now().toIso8601String(),
        'aquacoulisse': widget.aquacoulisse,
        'gasOut': _gasOut[name],
      });
    }
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Checked OUT ${selectedDivers.length} diver(s).");
    setState(() {
      selectedDivers.clear();
    });
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(selectedColor: widget.aquacoulisse),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final scale = appScale(context);

    final crossAxisCount = isPhone ? 2 : 4;
    final childAspect = isPhone ? 1.8 : 2.45;
    final gridSpacing = 12.0 * scale;

    final showDiversMode = selectedDepartmentFilter == null;

    final availableTeams = teamsWithCheckins;
    final hasShowTeamButtons = availableTeams.isNotEmpty;

    final List<Widget> leftTiles = [];
    if (showDiversMode) {
      final list = checkedInDiversForTeam;
      if (list.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              hasShowTeamButtons
                  ? "No checked-in divers for this team."
                  : "No divers checked in.",
              style: TextStyle(
                fontSize: (isPhone ? 18 : 22) * scale,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      } else {
        leftTiles.add(
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gridSpacing,
            crossAxisSpacing: gridSpacing,
            childAspectRatio: childAspect,
            children: [
              for (final d in list)
                Builder(
                  builder: (_) {
                    final name = d['name'] as String;
                    final waterIn = diverIsInWater(name);
                    final bool isSel = selectedDivers.contains(name);
                    final Color bg = isSel
                        ? Colors.green
                        : aquacoulisseColor(widget.aquacoulisse);
                    final int? tag = checkedInTank(name);
                    return Stack(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(120 * scale, 60 * scale),
                            backgroundColor: bg,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            textStyle: TextStyle(
                              fontSize: (isPhone ? 14 : 16) * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _toggleSelect(name),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tag == null
                                  ? name
                                  : "$name  (Tank ${tag.toString().padLeft(2, '0')})",
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: waterIn
                                  ? Colors.orange[600]
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              waterIn ? "IN" : "OUT",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else {
      final names = checkedInNamesForSelectedDepartment;
      if (names.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No one checked in from $selectedDepartmentFilter.",
              style: TextStyle(
                fontSize: (isPhone ? 18 : 22) * scale,
                color: Colors.grey[600],
              ),
            ),
          ),
        );
      } else {
        leftTiles.add(
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gridSpacing,
            crossAxisSpacing: gridSpacing,
            childAspectRatio: childAspect,
            children: [
              for (final name in names)
                Builder(
                  builder: (_) {
                    final waterIn = diverIsInWater(name);
                    final bool isSel = selectedDivers.contains(name);
                    final int? tag = checkedInTank(name);
                    final Color bg = isSel
                        ? Colors.green
                        : Colors.blueGrey; // neutral
                    return Stack(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(120 * scale, 60 * scale),
                            backgroundColor: bg,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            textStyle: TextStyle(
                              fontSize: (isPhone ? 14 : 16) * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _toggleSelect(name),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tag == null
                                  ? name
                                  : "$name  (Tank ${tag.toString().padLeft(2, '0')})",
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: waterIn
                                  ? Colors.orange[600]
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              waterIn ? "IN" : "OUT",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      }
    }

    final showTeamGroup = hasShowTeamButtons;
    final showDeptGroup = nonShowDepartmentsWithCheckins.isNotEmpty;
    final showAnyFilters = showTeamGroup || showDeptGroup;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn, onTap: _openLog),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(isPhone ? 6 : 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, size: 28 * scale),
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        tooltip: "Home",
                        icon: Icon(Icons.home_outlined, size: 26 * scale),
                        onPressed: () => Navigator.popUntil(
                          context,
                          (route) => route.isFirst,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 22 * scale,
                            vertical: 10 * scale,
                          ),
                          textStyle: TextStyle(
                            fontSize: 18 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _openLog,
                        child: const Text('  Log  '),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    "${widget.department} - ${widget.aquacoulisse} AQUACOULISSE",
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: aquacoulisseColor(widget.aquacoulisse),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),

                  if (showAnyFilters)
                    Wrap(
                      spacing: 6 * scale,
                      runSpacing: 6 * scale,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showTeamGroup)
                          for (final t in availableTeams)
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedDepartmentFilter = null;
                                  selectedTeam = t;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    (selectedDepartmentFilter == null &&
                                        selectedTeam == t)
                                    ? teamColor(t)
                                    : Colors.grey[100],
                                foregroundColor:
                                    (selectedDepartmentFilter == null &&
                                        selectedTeam == t)
                                    ? (t == "WHITE"
                                          ? Colors.black
                                          : Colors.white)
                                    : Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    18 * scale,
                                  ),
                                ),
                                elevation: 0,
                                minimumSize: Size(120 * scale, 48 * scale),
                                textStyle: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              child: Text("$t TEAM"),
                            ),
                        if (showTeamGroup && showDeptGroup)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * scale,
                            ),
                            child: Text(
                              "•",
                              style: TextStyle(
                                fontSize: 20 * scale,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        if (showDeptGroup)
                          for (final dep in nonShowDepartmentsWithCheckins)
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedDepartmentFilter = dep;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedDepartmentFilter == dep
                                    ? Colors.blueGrey[700]
                                    : Colors.grey[100],
                                foregroundColor: selectedDepartmentFilter == dep
                                    ? Colors.white
                                    : Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    18 * scale,
                                  ),
                                ),
                                elevation: 0,
                                minimumSize: Size(120 * scale, 48 * scale),
                                textStyle: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              child: Text(dep),
                            ),
                      ],
                    ),

                  if (showAnyFilters) SizedBox(height: 8 * scale),

                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: MediaQuery.of(context).size.width < 1200
                              ? 1
                              : 2,
                          child: leftTiles.isEmpty
                              ? const SizedBox.shrink()
                              : leftTiles.first,
                        ),
                        Expanded(
                          flex: 1,
                          child: LayoutBuilder(
                            builder: (ctx, constraints) {
                              return Container(
                                // Use right margin to visually shift the panel left without clipping
                                margin: EdgeInsets.only(
                                  right: MediaQuery.of(context).size.width > 700
                                      ? constraints.maxWidth * 0.01
                                      : 0,
                                ),
                                padding: EdgeInsets.symmetric(
                                  vertical: isPhone ? 12 * scale : 28 * scale,
                                  horizontal: 8 * scale,
                                ),
                                child: _buildSelectedPanel(isPhone, scale),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
