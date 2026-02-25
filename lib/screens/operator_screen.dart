import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../services/state_cache.dart';
import '../widgets/top_alert.dart';
import '../widgets/top_snack.dart';
import 'history_page.dart';

class _ShowDeckDragPayload {
  final String sourceDiverId;
  final Set<String> diverIds;

  const _ShowDeckDragPayload({
    required this.sourceDiverId,
    required this.diverIds,
  });
}

class OperatorScreen extends StatefulWidget {
  final bool showDeckMode;

  const OperatorScreen({super.key, this.showDeckMode = false});

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  late Box diversBox;
  late Box
  logsBox; // roster-related logs kept only for legacy, will no longer be source of truth
  late Box checkinsBox; // legacy local checkins (not authoritative)
  List<Map> divers = []; // roster with 'id' and 'name'
  String selectedTeam = teams.first;

  // When a non-Show-Divers department is selected, this is set.
  String? selectedDepartmentFilter;
  bool selectedAll = true; // default to show ALL checked-in divers
  bool selectedShowDiversOnly = false; // new tab: SHOW DIVERS (all teams)
  String? selectedAqcGroupFilter;
  final Map<String, String> _showDeckAqcOverride = {};

  static const List<String> _aqcGroups = ['BLUE', 'GREEN', 'RED', 'WHITE'];

  final Set<String> selectedDivers = {}; // diverIds (any department)
  // Optional gas values per selected diver (bars). In: default 200 for OUT divers, Out: default null ('-').
  final Map<String, int?> _gasIn = {}; // 0..250 or null
  final Map<String, int?> _gasOut = {}; // 0..250 or null
  int currentlyIn = 0;
  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _diversSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _logsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _showDeckAqcSub;

  Color _teamColor(String team) {
    switch (team.toUpperCase()) {
      case 'BLUE':
        return Colors.blue;
      case 'GREEN':
        return Colors.green;
      case 'RED':
        return Colors.red;
      case 'WHITE':
        return Colors.white;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    logsBox = Hive.box('logs');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _diversSub = FirebaseFirestore.instance
        .collection('divers')
        .snapshots()
        .listen((_) async {
          await _loadDivers();
        });
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen((_) {
          if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
        });
    _logsSub = FirebaseFirestore.instance.collection('logs').snapshots().listen(
      (_) {
        if (mounted) setState(() {});
      },
    );
    if (widget.showDeckMode) {
      _showDeckAqcSub = FirebaseFirestore.instance
          .collection('showdeck_aqc')
          .snapshots()
          .listen((snap) {
            final next = <String, String>{};
            for (final d in snap.docs) {
              final group = (d.data()['group'] ?? '').toString().toUpperCase();
              if (_aqcGroups.contains(group)) {
                next[d.id] = group;
              }
            }
            if (mounted) {
              setState(() {
                _showDeckAqcOverride
                  ..clear()
                  ..addAll(next);
              });
            }
          });
    }
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _loadDivers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('divers').get();
      final remote = [
        for (final d in snap.docs)
          {
            ...d.data(),
            'id': d.id,
            'name': (d.data()['name'] ?? d.id).toString(),
          },
      ];
      final list = remote.isNotEmpty
          ? remote.map((e) => Map<String, dynamic>.from(e)).toList()
          : List<Map>.from(diversBox.get('diversList', defaultValue: <Map>[]));
      divers = list;
    } catch (_) {
      final stored = diversBox.get('diversList', defaultValue: <Map>[]);
      final list = List<Map>.from(stored);
      divers = list;
    }
    // Ensure local fallback items have 'id'
    for (int i = 0; i < divers.length; i++) {
      final m = divers[i];
      if (!m.containsKey('id')) {
        divers[i] = {...m, 'id': (m['name'] ?? '').toString()};
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _tick() async {
    if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diversSub?.cancel();
    _checkinsSub?.cancel();
    _logsSub?.cancel();
    _showDeckAqcSub?.cancel();
    super.dispose();
  }

  // TEAMS that have at least one checked-in diver (for SHOW DIVERS only)
  List<String> get teamsWithCheckins {
    final Set<String> teamsSet = {};
    for (final id in StateCache.checkedInIds()) {
      final list = divers;
      final match = list.firstWhere(
        (d) => (d['id'] ?? '') == id,
        orElse: () => {},
      );
      if (_departmentForRecord(match) == "SHOW DIVERS") {
        final t = (match['team'] ?? '').toString().toUpperCase();
        if (t.isNotEmpty) teamsSet.add(t);
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

    final showDivers = divers.where(
      (d) => _departmentForRecord(d) == "SHOW DIVERS",
    );
    final teamDivers = showDivers.where((d) => (d['team'] ?? '') == useTeam);
    return teamDivers.where((d) => StateCache.isCheckedIn(d['id'])).toList();
  }

  String? _departmentForId(String id) {
    final list = divers;
    for (final d in list) {
      if ((d['id'] ?? '') == id) return (d['department'] ?? '').toString();
    }
    return null;
  }

  String _departmentForRecord(Map d) {
    return (d['department'] ?? '').toString();
  }

  String? _aqcGroupForId(String diverId) => _showDeckAqcOverride[diverId];

  Color _aqcColor(String group) {
    switch (group.toUpperCase()) {
      case 'BLUE':
        return Colors.blue;
      case 'GREEN':
        return Colors.green;
      case 'RED':
        return Colors.red;
      case 'WHITE':
        return Colors.white;
      default:
        return Colors.blueGrey;
    }
  }

  Set<String> _dragSelectionFor(String diverId) {
    if (!widget.showDeckMode) return {diverId};
    if (selectedDivers.isEmpty) return {diverId};
    final ids = <String>{...selectedDivers, diverId};
    return ids;
  }

  Future<void> _assignShowDeckAqcGroupBulk(
    Set<String> diverIds,
    String group,
  ) async {
    if (!widget.showDeckMode || diverIds.isEmpty) return;

    final toMove = [
      for (final id in diverIds)
        if (_aqcGroupForId(id) != group) id,
    ];
    if (toMove.isEmpty) return;

    setState(() {
      for (final id in toMove) {
        _showDeckAqcOverride[id] = group;
      }
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final coll = FirebaseFirestore.instance.collection('showdeck_aqc');
      for (final id in toMove) {
        batch.set(coll.doc(id), {
          'group': group,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
      _snack('Failed to save Show Deck AQC positions.');
      return;
    }

    if (toMove.length == 1) {
      final id = toMove.first;
      final rec = divers.firstWhere(
        (d) => (d['id'] ?? '').toString() == id,
        orElse: () => {'name': id},
      );
      final displayName = (rec['name'] ?? id).toString();
      _snack('$displayName moved to $group AQC (Show Deck only).');
    } else {
      _snack('${toMove.length} divers moved to $group AQC (Show Deck only).');
    }
  }

  Future<void> _clearShowDeckAqcGroupBulk(Set<String> diverIds) async {
    if (!widget.showDeckMode || diverIds.isEmpty) return;

    final toClear = [
      for (final id in diverIds)
        if ((_aqcGroupForId(id) ?? '').isNotEmpty) id,
    ];
    if (toClear.isEmpty) return;

    setState(() {
      for (final id in toClear) {
        _showDeckAqcOverride.remove(id);
      }
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final coll = FirebaseFirestore.instance.collection('showdeck_aqc');
      for (final id in toClear) {
        batch.delete(coll.doc(id));
      }
      await batch.commit();
    } catch (_) {
      _snack('Failed to remove Show Deck AQC positions.');
      return;
    }

    if (toClear.length == 1) {
      final id = toClear.first;
      final rec = divers.firstWhere(
        (d) => (d['id'] ?? '').toString() == id,
        orElse: () => {'name': id},
      );
      final displayName = (rec['name'] ?? id).toString();
      _snack('$displayName removed from AQC color (Show Deck only).');
    } else {
      _snack(
        '${toClear.length} divers removed from AQC colors (Show Deck only).',
      );
    }
  }

  List<String> get nonShowDepartmentsWithCheckins {
    final Set<String> depts = {};
    for (final id in StateCache.checkedInIds()) {
      final dept = _departmentForId(id);
      if (dept != null && dept != "SHOW DIVERS") {
        depts.add(dept);
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
    final deptNames = divers
        .where((d) => _departmentForRecord(d) == selectedDepartmentFilter)
        .map((d) => (d['id'] ?? '').toString())
        .where((id) => id.isNotEmpty && StateCache.isCheckedIn(id))
        .toList();
    deptNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return deptNames;
  }

  // All currently checked-in diver IDs (across all departments)
  List<String> get allCheckedInNames {
    // Source from StateCache checkins map to avoid roster dependency
    return StateCache.checkedInIds();
  }

  void _snack(String m) {
    TopSnack.show(context, m, duration: const Duration(seconds: 2));
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
                        // Show most recent selections at the top
                        for (final id in selectedDivers.toList().reversed)
                          DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    divers.firstWhere(
                                          (d) => d['id'] == id,
                                          orElse: () => {'name': id},
                                        )['name']
                                        as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 46,
                                  child: InkWell(
                                    onTap: () async {
                                      // Prevent changing tank while diver is IN WATER
                                      if (StateCache.diverIsInWater(id)) {
                                        _snack(
                                          "Cannot change tank while diver is IN WATER.",
                                        );
                                        return;
                                      }
                                      final currentTag =
                                          StateCache.checkedInTank(id);
                                      final newTag = await _editTagNumber(
                                        context,
                                        initial: currentTag,
                                        title: 'Tank number',
                                      );
                                      if (newTag != null) {
                                        await StateCache.setCheckin(
                                          id,
                                          checkedIn: true,
                                          tag: newTag,
                                        );
                                        if (mounted) setState(() {});
                                      }
                                    },
                                    child: Text(
                                      StateCache.checkedInTank(
                                            id,
                                          )?.toString().padLeft(2, '0') ??
                                          '--',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
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
                                        initial: _gasIn[id],
                                        title: 'Gas In (bar)',
                                      );
                                      setState(() => _gasIn[id] = v);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6.0,
                                      ),
                                      child: Text(
                                        _gasIn[id] == null
                                            ? '-'
                                            : '${_gasIn[id]}bar',
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
                                        initial: _gasOut[id],
                                        title: 'Gas Out (bar)',
                                      );
                                      setState(() => _gasOut[id] = v);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6.0,
                                      ),
                                      child: Text(
                                        _gasOut[id] == null
                                            ? '? bar'
                                            : '${_gasOut[id]}bar',
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
                                    StateCache.diverIsInWater(id)
                                        ? 'In'
                                        : 'Out',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 28,
                                  child: Center(
                                    child: InkWell(
                                      onTap: () => _toggleSelect(id),
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
                onPressed: (allSelectedAreOut && allSelectedHaveTank)
                    ? _batchIn
                    : null,
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
      selectedDivers.every((id) => StateCache.diverIsInWater(id));
  bool get allSelectedAreOut =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((id) => !StateCache.diverIsInWater(id));
  bool get allSelectedHaveTank =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((id) => StateCache.checkedInTank(id) != null);
  bool get mixedSelection =>
      selectedDivers.isNotEmpty && !(allSelectedAreIn || allSelectedAreOut);

  void _toggleSelect(String id) {
    setState(() {
      if (selectedDivers.contains(id)) {
        selectedDivers.remove(id);
      } else {
        selectedDivers.add(id);
        _gasIn.putIfAbsent(id, () => 200); // default
        _gasOut.putIfAbsent(id, () => null); // unknown by default -> '? bar'
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

  Future<int?> _editTagNumber(
    BuildContext context, {
    int? initial,
    required String title,
  }) async {
    final controller = TextEditingController(
      text: initial == null ? '' : initial.toString(),
    );
    int? result = initial;
    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Tank # (0 - 99)'),
            maxLength: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = controller.text.trim();
                final val = int.tryParse(txt);
                if (val != null && val >= 0 && val <= 99) {
                  result = val;
                } else {
                  result = null;
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
    final missingTankIds = [
      for (final id in selectedDivers)
        if (StateCache.checkedInTank(id) == null) id,
    ];
    if (missingTankIds.isNotEmpty) {
      final names = [
        for (final id in missingTankIds)
          (divers.firstWhere(
                    (d) => d['id'] == id,
                    orElse: () => {'name': id},
                  )['name'] ??
                  id)
              .toString(),
      ];
      final who = names.take(3).join(', ');
      final suffix = names.length > 3 ? ' and ${names.length - 3} more' : '';
      _snack('Assign tank before IN: $who$suffix.');
      return;
    }
    final now = DateTime.now().toIso8601String();
    final payload = <Map<String, dynamic>>[];
    for (final id in selectedDivers) {
      final tag = StateCache.checkedInTank(id);
      final displayName = divers.firstWhere(
        (d) => d['id'] == id,
        orElse: () => {'name': id},
      )['name'];
      payload.add({
        'diverId': id,
        'name': displayName,
        'status': 'IN',
        'tag': tag ?? '',
        'datetime': now,
        'gasIn': _gasIn[id],
      });
      await StateCache.setCheckin(id, checkedIn: true, tag: tag);
    }
    await StateCache.addLogs(payload);
    await _playConfirm();
    _snack("Checked IN ${selectedDivers.length} diver(s).");
    setState(() => selectedDivers.clear());
  }

  Future<void> _batchOut() async {
    if (!allSelectedAreIn) return;
    final now = DateTime.now().toIso8601String();
    final payload = <Map<String, dynamic>>[];
    for (final id in selectedDivers) {
      final tag = StateCache.checkedInTank(id);
      final displayName = divers.firstWhere(
        (d) => d['id'] == id,
        orElse: () => {'name': id},
      )['name'];
      payload.add({
        'diverId': id,
        'name': displayName,
        'status': 'OUT',
        'tag': tag ?? '',
        'datetime': now,
        'gasOut': _gasOut[id],
      });
      // Do not uncheck from deck when sending OUT of water.
      // Keep the diver checked-in with the same tag.
      await StateCache.setCheckin(id, checkedIn: true, tag: tag);
    }
    await StateCache.addLogs(payload);
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
        builder: (_) => const HistoryPage(selectedColor: "IN WATER"),
      ),
    );
  }

  // Build a segmented diver tile where the status (IN/OUT) is part of the button
  // as a colored right-hand segment to avoid overlapping on small screens.
  Widget _segmentedDiverButton({
    required String diverId,
    required String title,
    String? subtitle,
    required bool waterIn,
    required bool selected,
    required double scale,
    double verticalFactor = 1.0,
    required VoidCallback onTap,
  }) {
    final Color baseBg = selected ? Colors.green : Colors.blueGrey;
    final Color statusBg = waterIn
        ? (Colors.orange[700] ?? Colors.orange)
        : Colors.black87;
    final String statusTxt = waterIn ? 'IN' : 'OUT';
    final double radius = 18 * scale;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: Size(112 * scale, 52 * scale * verticalFactor),
        backgroundColor: baseBg,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        textStyle: TextStyle(
          fontSize: (MediaQuery.of(context).size.width < 600 ? 16 : 18) * scale,
          fontWeight: FontWeight.bold,
        ),
        elevation: 0,
        padding: EdgeInsets.zero,
      ),
      onPressed: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * scale,
                  vertical: 8 * scale,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 2 * verticalFactor),
                          child: Builder(
                            builder: (_) {
                              final baseStyle = TextStyle(
                                fontSize: 13 * scale,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              );
                              // Expect pattern like "SHOW DIVERS - BLUE"; color the team word.
                              final parts = subtitle.split(' - ');
                              if (parts.length == 2) {
                                final left = parts[0];
                                final team = parts[1].trim().toUpperCase();
                                Color teamColor;
                                switch (team) {
                                  case 'BLUE':
                                    teamColor = Colors.blue[300] ?? Colors.blue;
                                    break;
                                  case 'GREEN':
                                    teamColor =
                                        Colors.green[300] ?? Colors.green;
                                    break;
                                  case 'RED':
                                    teamColor = Colors.red[300] ?? Colors.red;
                                    break;
                                  case 'WHITE':
                                    teamColor = Colors.white;
                                    break;
                                  default:
                                    teamColor = Colors.white70;
                                }
                                return Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$left - ',
                                        style: baseStyle,
                                      ),
                                      TextSpan(
                                        text: team,
                                        style: baseStyle.copyWith(
                                          color: teamColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              // Fallback: render as a single-colored subtitle
                              return Text(subtitle, style: baseStyle);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                alignment: Alignment.center,
                color: statusBg,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                    child: Text(
                      statusTxt,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize:
                            (MediaQuery.of(context).size.width < 600
                                ? 20
                                : 22) *
                            scale,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiverTile({
    required String diverId,
    required String title,
    required String subtitle,
    required bool waterIn,
    required bool selected,
    required double scale,
    required double verticalFactor,
  }) {
    final baseTile = _segmentedDiverButton(
      diverId: diverId,
      title: title,
      subtitle: subtitle,
      waterIn: waterIn,
      selected: selected,
      scale: scale,
      verticalFactor: verticalFactor,
      onTap: () => _toggleSelect(diverId),
    );

    if (!widget.showDeckMode) return baseTile;

    return LongPressDraggable<_ShowDeckDragPayload>(
      data: _ShowDeckDragPayload(
        sourceDiverId: diverId,
        diverIds: _dragSelectionFor(diverId),
      ),
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 280 * scale),
          child: Opacity(opacity: 0.95, child: baseTile),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: baseTile),
      child: baseTile,
    );
  }

  Widget _buildShowDeckDropTarget({
    required String aqcGroup,
    required bool selected,
    required double scale,
  }) {
    return DragTarget<_ShowDeckDragPayload>(
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        if (payload.diverIds.isEmpty) return false;
        return payload.diverIds.any((id) => _aqcGroupForId(id) != aqcGroup);
      },
      onAcceptWithDetails: (details) {
        _assignShowDeckAqcGroupBulk(details.data.diverIds, aqcGroup);
      },
      builder: (context, candidateData, rejectedData) {
        final bool hovering = candidateData.isNotEmpty;
        final Color groupColor = _aqcColor(aqcGroup);
        final bool isWhite = aqcGroup.toUpperCase() == 'WHITE';
        return ElevatedButton(
          onPressed: () {
            setState(() {
              if (!selectedAll && selectedAqcGroupFilter == aqcGroup) {
                selectedAll = true;
                selectedAqcGroupFilter = null;
              } else {
                selectedAll = false;
                selectedAqcGroupFilter = aqcGroup;
              }
              selectedShowDiversOnly = false;
              selectedDepartmentFilter = null;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: hovering
                ? Colors.amber[200]
                : (selected ? groupColor : Colors.grey[100]),
            foregroundColor: selected
                ? (isWhite ? Colors.black : Colors.white)
                : Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18 * scale),
            ),
            side: selected
                ? BorderSide(
                    color: isWhite ? Colors.black26 : groupColor,
                    width: 1.2,
                  )
                : BorderSide.none,
            elevation: 0,
            minimumSize: Size(120 * scale, 44 * scale),
            textStyle: TextStyle(
              fontSize: 13 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: Text('$aqcGroup AQC'),
        );
      },
    );
  }

  Widget _buildShowDeckAllDropTarget({required double scale}) {
    return DragTarget<_ShowDeckDragPayload>(
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        if (payload.diverIds.isEmpty) return false;
        return payload.diverIds.any((id) {
          final group = _aqcGroupForId(id);
          return group != null && group.isNotEmpty;
        });
      },
      onAcceptWithDetails: (details) {
        _clearShowDeckAqcGroupBulk(details.data.diverIds);
      },
      builder: (context, candidateData, rejectedData) {
        final bool hovering = candidateData.isNotEmpty;
        return ElevatedButton(
          onPressed: () {
            setState(() {
              selectedAll = true;
              selectedAqcGroupFilter = null;
              selectedShowDiversOnly = false;
              selectedDepartmentFilter = null;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: hovering
                ? Colors.amber[200]
                : (selectedAll ? Colors.blueGrey[700] : Colors.grey[100]),
            foregroundColor: selectedAll ? Colors.white : Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18 * scale),
            ),
            elevation: 0,
            minimumSize: Size(96 * scale, 44 * scale),
            textStyle: TextStyle(
              fontSize: 13 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: const Text('ALL'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isPhone = screenSize.width < 600;
    final bool isTablet = !isPhone && screenSize.width < 1100; // iPad range
    final scale = appScale(context);
    final double tileScale = isTablet
        ? scale * 1.6
        : scale; // slightly smaller overall
    final double verticalFactor = isTablet ? (2.0 / 3.0) : 1.0; // ~1/3 thinner

    final crossAxisCount = isPhone ? 2 : (isTablet ? 2 : 4);
    final childAspect = isPhone
        ? 2.2
        : (isTablet ? 2.7 : 3.0); // thinner tiles on tablets
    final gridSpacing = 12.0 * scale;

    // Distinguish between team mode and the new "SHOW DIVERS" tab.
    final bool showDiversOnlyMode = selectedShowDiversOnly;
    final bool teamMode =
        !selectedAll &&
        selectedDepartmentFilter == null &&
        !selectedShowDiversOnly;

    // Team color filters removed; only department filters and ALL remain.

    final List<Widget> leftTiles = [];
    if (widget.showDeckMode) {
      final names = allCheckedInNames.where((id) {
        if (selectedAll || selectedAqcGroupFilter == null) return true;
        return _aqcGroupForId(id) == selectedAqcGroupFilter;
      }).toList();

      if (names.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              selectedAqcGroupFilter == null
                  ? "No divers checked in."
                  : "No divers in ${selectedAqcGroupFilter!} AQC.",
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
              for (final id in names)
                Builder(
                  builder: (_) {
                    final waterIn = StateCache.diverIsInWater(id);
                    final bool isSel = selectedDivers.contains(id);
                    final int? tag = StateCache.checkedInTank(id);
                    final rec = divers.firstWhere(
                      (d) => d['id'] == id,
                      orElse: () => const {},
                    );
                    final displayName = (rec['name'] ?? id).toString();
                    final String? aqcGroup = _aqcGroupForId(id);
                    final String dep = (rec['department'] ?? '').toString();
                    final String team = (rec['team'] ?? '').toString();
                    final String subtitle = aqcGroup != null
                        ? 'AQC - $aqcGroup'
                        : (dep == 'SHOW DIVERS' && team.isNotEmpty
                              ? '$dep - $team'
                              : dep);
                    final String titleText = tag == null
                        ? '$displayName  (NO TANK)'
                        : "$displayName  (Tank ${tag.toString().padLeft(2, '0')})";
                    return _buildDiverTile(
                      diverId: id,
                      title: titleText,
                      subtitle: subtitle,
                      waterIn: waterIn,
                      selected: isSel,
                      scale: tileScale,
                      verticalFactor: verticalFactor,
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else if (selectedAll) {
      final names = allCheckedInNames; // now diverIds
      if (names.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No divers checked in.",
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
              for (final id in names)
                Builder(
                  builder: (_) {
                    final waterIn = StateCache.diverIsInWater(id);
                    final bool isSel = selectedDivers.contains(id);
                    final int? tag = StateCache.checkedInTank(id);
                    final displayName = divers.firstWhere(
                      (d) => d['id'] == id,
                      orElse: () => {'name': id},
                    )['name'];
                    // Use neutral color for ALL listing
                    final rec = divers.firstWhere(
                      (d) => d['id'] == id,
                      orElse: () => const {},
                    );
                    final String dep = _departmentForRecord(rec);
                    final String team = (rec['team'] ?? '').toString();
                    String subtitle = '';
                    if (dep.isNotEmpty) {
                      subtitle = dep == 'SHOW DIVERS' && team.isNotEmpty
                          ? '$dep - $team'
                          : dep;
                    }
                    final String titleText = tag == null
                        ? '$displayName  (NO TANK)'
                        : "$displayName  (Tank ${tag.toString().padLeft(2, '0')})";
                    return _buildDiverTile(
                      diverId: id,
                      title: titleText,
                      subtitle: subtitle,
                      waterIn: waterIn,
                      selected: isSel,
                      scale: tileScale,
                      verticalFactor: verticalFactor,
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else if (teamMode) {
      final list = checkedInDiversForTeam;
      if (list.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No divers checked in.",
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
                    final String id = (d['id'] ?? '').toString();
                    final String name = (d['name'] ?? '').toString();
                    final waterIn = StateCache.diverIsInWater(id);
                    final bool isSel = selectedDivers.contains(id);
                    final int? tag = StateCache.checkedInTank(id);
                    final String titleText = tag == null
                        ? '$name  (NO TANK)'
                        : "$name  (Tank ${tag.toString().padLeft(2, '0')})";
                    return _buildDiverTile(
                      diverId: id,
                      title: titleText,
                      waterIn: waterIn,
                      selected: isSel,
                      subtitle: '',
                      scale: tileScale,
                      verticalFactor: verticalFactor,
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else if (showDiversOnlyMode) {
      // SHOW DIVERS tab (all teams under the SHOW DIVERS department)
      final showDiversAll = divers
          .where((d) => _departmentForRecord(d) == 'SHOW DIVERS')
          .where((d) => StateCache.isCheckedIn((d['id'] ?? '').toString()))
          .toList();
      // Sort by name for readability
      showDiversAll.sort(
        (a, b) => ((a['name'] ?? '').toString()).toLowerCase().compareTo(
          ((b['name'] ?? '').toString()).toLowerCase(),
        ),
      );
      if (showDiversAll.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No divers checked in.",
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
              for (final d in showDiversAll)
                Builder(
                  builder: (_) {
                    final String id = (d['id'] ?? '').toString();
                    final String name = (d['name'] ?? '').toString();
                    final String team = (d['team'] ?? '').toString();
                    final bool waterIn = StateCache.diverIsInWater(id);
                    final bool isSel = selectedDivers.contains(id);
                    final int? tag = StateCache.checkedInTank(id);
                    final String titleText = tag == null
                        ? name
                        : "$name  (Tank ${tag.toString().padLeft(2, '0')})";
                    // Provide colored subtitle for SHOW DIVERS entries
                    final String subtitle = team.isNotEmpty
                        ? 'SHOW DIVERS - ${team.toUpperCase()}'
                        : 'SHOW DIVERS';
                    return _buildDiverTile(
                      diverId: id,
                      title: titleText,
                      subtitle: subtitle,
                      waterIn: waterIn,
                      selected: isSel,
                      scale: tileScale,
                      verticalFactor: verticalFactor,
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else {
      final names = checkedInNamesForSelectedDepartment; // ids
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
              for (final id in names)
                Builder(
                  builder: (_) {
                    final waterIn = StateCache.diverIsInWater(id);
                    final bool isSel = selectedDivers.contains(id);
                    final int? tag = StateCache.checkedInTank(id);
                    final displayName = divers.firstWhere(
                      (d) => d['id'] == id,
                      orElse: () => {'name': id},
                    )['name'];
                    final String titleText = tag == null
                        ? '$displayName  (NO TANK)'
                        : "$displayName  (Tank ${tag.toString().padLeft(2, '0')})";
                    final rec = divers.firstWhere(
                      (d) => d['id'] == id,
                      orElse: () => const {},
                    );
                    final String dep = _departmentForRecord(rec);
                    final String team = (rec['team'] ?? '').toString();
                    final String subtitle =
                        dep == 'SHOW DIVERS' && team.isNotEmpty
                        ? '$dep - $team'
                        : dep;
                    return _buildDiverTile(
                      diverId: id,
                      title: titleText,
                      waterIn: waterIn,
                      selected: isSel,
                      subtitle: subtitle,
                      scale: tileScale,
                      verticalFactor: verticalFactor,
                    );
                  },
                ),
            ],
          ),
        );
      }
    }

    final availableTeams = teamsWithCheckins;
    final showTeamGroup = availableTeams.isNotEmpty;
    final bool hasShowDivers = showTeamGroup;
    final showDeptGroup = nonShowDepartmentsWithCheckins.isNotEmpty;
    final showAnyFilters = showTeamGroup || showDeptGroup || hasShowDivers;

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
                    widget.showDeckMode ? "Show Deck" : "Deck Operator",
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[700],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),

                  if (widget.showDeckMode)
                    Column(
                      children: [
                        Text(
                          'Long-press and drag a diver onto an AQC color to group them. Selected divers move together.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.blueGrey[600],
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                        Wrap(
                          spacing: 6 * scale,
                          runSpacing: 6 * scale,
                          children: [
                            _buildShowDeckAllDropTarget(scale: scale),
                            for (final group in _aqcGroups)
                              _buildShowDeckDropTarget(
                                aqcGroup: group,
                                selected:
                                    !selectedAll &&
                                    selectedAqcGroupFilter == group,
                                scale: scale,
                              ),
                          ],
                        ),
                        SizedBox(height: 8 * scale),
                      ],
                    ),

                  if (!widget.showDeckMode && showAnyFilters)
                    Wrap(
                      spacing: 6 * scale,
                      runSpacing: 6 * scale,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // ALL tab first
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              selectedAll = true;
                              selectedDepartmentFilter = null;
                              selectedShowDiversOnly = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedAll
                                ? Colors.blueGrey[700]
                                : Colors.grey[100],
                            foregroundColor: selectedAll
                                ? Colors.white
                                : Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18 * scale),
                            ),
                            elevation: 0,
                            minimumSize: Size(120 * scale, 48 * scale),
                            textStyle: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text('ALL'),
                        ),

                        if (hasShowDivers)
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                selectedAll = false;
                                selectedDepartmentFilter = null;
                                selectedShowDiversOnly = true;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedShowDiversOnly
                                  ? Colors.blueGrey[700]
                                  : Colors.grey[100],
                              foregroundColor: selectedShowDiversOnly
                                  ? Colors.white
                                  : Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18 * scale),
                              ),
                              elevation: 0,
                              minimumSize: Size(160 * scale, 48 * scale),
                              textStyle: TextStyle(
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: const Text('SHOW DIVERS'),
                          ),

                        if (showTeamGroup)
                          for (final t in availableTeams)
                            Builder(
                              builder: (context) {
                                final bool isSelected =
                                    (!selectedAll &&
                                    selectedDepartmentFilter == null &&
                                    selectedTeam == t &&
                                    !selectedShowDiversOnly);
                                final Color teamBg = isSelected
                                    ? _teamColor(t)
                                    : (Colors.grey[100]!);
                                final Color teamFg = isSelected
                                    ? (t.toUpperCase() == 'WHITE'
                                          ? Colors.black
                                          : Colors.white)
                                    : Colors.black;
                                return ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedAll = false;
                                      selectedDepartmentFilter = null;
                                      selectedShowDiversOnly = false;
                                      selectedTeam = t;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: teamBg,
                                    foregroundColor: teamFg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        18 * scale,
                                      ),
                                    ),
                                    elevation: 0,
                                    side: isSelected
                                        ? BorderSide(
                                            color: t.toUpperCase() == 'WHITE'
                                                ? Colors.black26
                                                : teamBg,
                                            width: 1.2,
                                          )
                                        : BorderSide.none,
                                    minimumSize: Size(120 * scale, 48 * scale),
                                    textStyle: TextStyle(
                                      fontSize: 14 * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: Text("${t.toUpperCase()} TEAM"),
                                );
                              },
                            ),

                        if (!widget.showDeckMode && showDeptGroup)
                          for (final dep in nonShowDepartmentsWithCheckins)
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedAll = false;
                                  selectedDepartmentFilter = dep;
                                  selectedShowDiversOnly = false;
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
                    child: LayoutBuilder(
                      builder: (ctx, outer) {
                        // Build the right (Selected) panel once; center it within its space and constrain max width for large screens.
                        Widget rightPanel = LayoutBuilder(
                          builder: (ctx2, constraints) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  // Keep the table from stretching too wide on web desktops
                                  maxWidth: constraints.maxWidth
                                      .clamp(0, 640)
                                      .toDouble(),
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isPhone ? 12 * scale : 28 * scale,
                                    horizontal: 8 * scale,
                                  ),
                                  child: _buildSelectedPanel(isPhone, scale),
                                ),
                              ),
                            );
                          },
                        );

                        final screenW = MediaQuery.of(context).size.width;
                        if (screenW < 700) {
                          // On phones: stack vertically so the Selected table gets full width and sits below the tiles.
                          return Column(
                            children: [
                              Expanded(
                                child: leftTiles.isEmpty
                                    ? const SizedBox.shrink()
                                    : leftTiles.first,
                              ),
                              const Divider(height: 1),
                              Expanded(child: rightPanel),
                            ],
                          );
                        }

                        // On tablets/desktop: two columns side‑by‑side with centered right panel; no magic margins.
                        return Row(
                          children: [
                            Expanded(
                              flex: screenW < 1200 ? 1 : 2,
                              child: leftTiles.isEmpty
                                  ? const SizedBox.shrink()
                                  : leftTiles.first,
                            ),
                            Expanded(flex: 1, child: rightPanel),
                          ],
                        );
                      },
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
