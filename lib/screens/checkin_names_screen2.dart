import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/navigation.dart';
import '../core/utils.dart';
import '../services/state_cache.dart';
import '../widgets/top_alert.dart';
import '../widgets/top_snack.dart';
import 'history_page.dart';

class CheckInNamesScreen2 extends StatefulWidget {
  final String department;
  const CheckInNamesScreen2({super.key, required this.department});

  @override
  State<CheckInNamesScreen2> createState() => _CheckInNamesScreen2State();
}

class _CheckInNamesScreen2State extends State<CheckInNamesScreen2> {
  late Box diversBox;
  late Box checkinsBox;

  List<Map> divers = [];
  String selectedTeam = teams.first;
  String? selectedDiver; // diverId
  String? selectedDiverName; // display name
  int? selectedTag;
  final TextEditingController _tankController = TextEditingController();
  static const int _maxTank = 999; // allow 3 digits

  int currentlyIn = 0;
  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _diversSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;

  bool get isShowDivers => widget.department == 'SHOW DIVERS';
  bool get isOtherAggregated => widget.department == 'OTHER';
  String? selectedSubDepartment; // drill-down for OTHER
  // Cache of OTHER sub-department counts built from the latest roster
  Map<String, int> _otherCounts = {};

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Live updates: listen to Firestore roster and checkins changes
    _diversSub = FirebaseFirestore.instance
        .collection('divers')
        .snapshots()
        .listen(
          (_) {
            _loadDivers();
          },
          onError: (_, __) {
            _loadDivers();
          },
        );
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen(
          (_) {
            if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
          },
          onError: (_, __) {
            if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
          },
        );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diversSub?.cancel();
    _checkinsSub?.cancel();
    _tankController.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    List<Map> list = List<Map>.from(stored);
    // Try Firestore roster; if available, prefer it
    FirebaseFirestore.instance
        .collection('divers')
        .get()
        .then((snap) {
          final remote = [
            for (final d in snap.docs)
              {
                ...d.data(),
                'id': d.id,
                'name': (d.data()['name'] ?? d.id).toString(),
              },
          ];
          if (remote.isNotEmpty) {
            list = remote.map((e) => Map<String, dynamic>.from(e)).toList();
          }
          // Rebuild OTHER sub-department counts from the roster
          final Map<String, int> counts = {};
          for (final d in list) {
            final dep = (d['department'] ?? '').toString();
            if (dep.isEmpty) continue;
            if (dep == 'SHOW DIVERS' || dep == 'DAY CREW') continue;
            counts[dep] = (counts[dep] ?? 0) + 1;
          }
          _otherCounts = counts;
          if (isOtherAggregated) {
            if (selectedSubDepartment != null) {
              divers = list
                  .where((d) => d['department'] == selectedSubDepartment)
                  .toList();
            } else {
              divers = [];
            }
          } else {
            divers = list
                .where((d) => d['department'] == widget.department)
                .toList();
          }
          if (mounted) setState(() {});
        })
        .catchError((_) {
          // Fallback to Hive-only
          final Map<String, int> counts = {};
          for (final d in list) {
            final dep = (d['department'] ?? '').toString();
            if (dep.isEmpty) continue;
            if (dep == 'SHOW DIVERS' || dep == 'DAY CREW') continue;
            counts[dep] = (counts[dep] ?? 0) + 1;
          }
          _otherCounts = counts;
          if (isOtherAggregated) {
            if (selectedSubDepartment != null) {
              divers = list
                  .where((d) => d['department'] == selectedSubDepartment)
                  .toList();
            } else {
              divers = [];
            }
          } else {
            divers = list
                .where((d) => d['department'] == widget.department)
                .toList();
          }
          if (mounted) setState(() {});
        });
  }

  void _applyInput(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    String trimmed = digits.replaceFirst(RegExp(r'^0+'), '');
    if (trimmed.isEmpty) {
      setState(() {
        // Avoid modifying controller selection unexpectedly; clear safely
        if (_tankController.text.isNotEmpty) {
          _tankController.text = '';
          _tankController.selection = const TextSelection.collapsed(offset: 0);
        }
        selectedTag = null;
      });
      return;
    }
    if (trimmed.length > 3) trimmed = trimmed.substring(0, 3);
    final val = int.tryParse(trimmed);
    setState(() {
      // Only update the controller text if it actually changed to prevent
      // caret jumping and character overwrite on some platforms (web/desktop).
      if (_tankController.text != trimmed) {
        _tankController.text = trimmed;
        _tankController.selection = TextSelection.collapsed(
          offset: _tankController.text.length,
        );
      }
      if (val == null || val < 1 || val > _maxTank) {
        selectedTag = null;
      } else {
        selectedTag = val;
      }
    });
  }

  List<Map> get displayedDivers {
    if (isShowDivers) {
      return divers.where((d) => d['team'] == selectedTeam).toList();
    }
    return divers;
  }

  // Checked-in divers for the current context (department or SHOW DIVERS team)
  List<Map<String, dynamic>> get checkedInDiversForContext {
    final ids = StateCache.checkedInIds();
    final List<Map<String, dynamic>> out = [];
    for (final id in ids) {
      // Find roster record for id
      final rec = divers.firstWhere(
        (d) => (d['id'] ?? '') == id,
        orElse: () => const {},
      );
      if (rec.isEmpty) continue;
      // Apply filters for context
      if (isShowDivers) {
        if ((rec['team'] ?? '') != selectedTeam) continue;
      } else if (isOtherAggregated) {
        if (selectedSubDepartment == null) continue;
        if ((rec['department'] ?? '') != selectedSubDepartment) continue;
      } else {
        if ((rec['department'] ?? '') != widget.department) continue;
      }
      out.add({
        'id': id,
        'name': (rec['name'] ?? id).toString(),
        'tag': StateCache.checkedInTank(id),
      });
    }
    out.sort(
      (a, b) => (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      ),
    );
    return out;
  }

  void _snack(String msg) {
    TopSnack.show(context, msg, duration: const Duration(seconds: 2));
  }

  void _cancel() {
    setState(() {
      selectedDiver = null;
      selectedDiverName = null;
      selectedTag = null;
      _tankController.clear();
    });
  }

  void _confirm() async {
    if (selectedDiver == null) {
      _snack('Please select a diver.');
      return;
    }
    if (StateCache.isCheckedIn(selectedDiver!)) {
      _snack('Already checked in. Change tank from Log → Checked‑In.');
      return;
    }
    await StateCache.setCheckin(
      selectedDiver!,
      checkedIn: true,
      tag: selectedTag,
    );
    // Build notice if others have the same tank
    String msg;
    if (selectedTag == null) {
      msg = 'Checked in ${selectedDiverName ?? 'diver'} with no tank.';
    } else {
      final String tagStr = selectedTag!.toString().padLeft(2, '0');
      final ids = StateCache.checkedInIds();
      final List<String> others = [];
      for (final oid in ids) {
        if (oid == selectedDiver) continue;
        final t = StateCache.checkedInTank(oid);
        if (t == selectedTag) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('divers')
                .doc(oid)
                .get();
            final oname = (doc.data()?['name'] ?? oid).toString();
            others.add(oname);
          } catch (_) {
            others.add(oid);
          }
        }
      }
      msg = 'Checked in ${selectedDiverName ?? 'diver'} with tank $tagStr.';
      if (others.isNotEmpty) {
        msg += others.length == 1
            ? ' Note: ${others.first} also uses tank $tagStr.'
            : ' Note: ${others.join(', ')} also use tank $tagStr.';
      }
    }
    _snack(msg);
    _cancel();
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistoryPage(selectedColor: 'ALL'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final isPhone = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = isPhone ? 2 : 4;
    final childAspect = isPhone ? 1.8 : 2.45;
    final gridSpacing = 12.0 * scale;

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
                        tooltip: 'Home',
                        icon: Icon(Icons.home_outlined, size: 26 * scale),
                        onPressed: () => goHome(context),
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
                    isOtherAggregated
                        ? (selectedSubDepartment == null
                              ? 'OTHER DEPARTMENTS - SELECT DEPARTMENT'
                              : '${selectedSubDepartment} - CHECK IN')
                        : '${widget.department} - CHECK IN',
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),

                  if (isShowDivers)
                    Wrap(
                      spacing: 6 * scale,
                      runSpacing: 6 * scale,
                      children: [
                        for (final t in teams)
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                selectedTeam = t;
                                selectedDiver = null;
                                selectedTag = null;
                                _tankController.clear();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedTeam == t
                                  ? teamColor(t)
                                  : Colors.grey[100],
                              foregroundColor: selectedTeam == t
                                  ? (t == 'WHITE' ? Colors.black : Colors.white)
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
                            child: Text('$t TEAM'),
                          ),
                      ],
                    ),

                  if (isShowDivers) SizedBox(height: 8 * scale),

                  if (isOtherAggregated && selectedSubDepartment == null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8 * scale),
                      child: Builder(
                        builder: (_) {
                          final counts = _otherCounts;
                          final deps = counts.keys.toList()..sort();
                          if (deps.isEmpty) {
                            return Center(
                              child: Text(
                                'No departments found.',
                                style: TextStyle(
                                  fontSize: (isPhone ? 18 : 22) * scale,
                                  color: Colors.grey[600],
                                ),
                              ),
                            );
                          }
                          return Wrap(
                            spacing: 10 * scale,
                            runSpacing: 10 * scale,
                            children: [
                              for (final dep in deps)
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedSubDepartment = dep;
                                      selectedDiver = null;
                                      selectedTag = null;
                                      _loadDivers();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey[700],
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(160 * scale, 54 * scale),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        30 * scale,
                                      ),
                                    ),
                                    textStyle: TextStyle(
                                      fontSize: 16 * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    counts[dep] != null
                                        ? '$dep (${counts[dep]})'
                                        : dep,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                  Expanded(
                    child: Row(
                      children: [
                        // Left panel
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              if (isOtherAggregated &&
                                  selectedSubDepartment == null)
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'Select a department above.',
                                      style: TextStyle(
                                        fontSize: (isPhone ? 18 : 22) * scale,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                )
                              else if (selectedDiver == null)
                                Expanded(
                                  child: displayedDivers.isEmpty
                                      ? Center(
                                          child: Text(
                                            'No names found.\nAdd in Settings.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 18 : 22) * scale,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        )
                                      : GridView.count(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: gridSpacing,
                                          crossAxisSpacing: gridSpacing,
                                          childAspectRatio: childAspect,
                                          children: [
                                            for (final person
                                                in displayedDivers)
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  minimumSize: Size(
                                                    120 * scale,
                                                    60 * scale,
                                                  ),
                                                  backgroundColor: isShowDivers
                                                      ? teamColor(selectedTeam)
                                                      : Colors.blueGrey,
                                                  foregroundColor:
                                                      (isShowDivers &&
                                                          selectedTeam ==
                                                              'WHITE')
                                                      ? Colors.black
                                                      : Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          22 * scale,
                                                        ),
                                                  ),
                                                  textStyle: TextStyle(
                                                    fontSize:
                                                        (isPhone ? 14 : 16) *
                                                        scale,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  elevation: 0,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    selectedDiver =
                                                        (person['id'] ?? '')
                                                            .toString();
                                                    selectedDiverName =
                                                        (person['name'] ?? '')
                                                            .toString();
                                                    selectedTag = null;
                                                    _tankController.clear();
                                                  });
                                                },
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    person['name'] ?? '',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),

                              if (selectedDiver != null)
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      // Revert to transform-based positioning per user preference
                                      final dx =
                                          constraints.maxWidth *
                                          0.25; // move right 25%
                                      final dy =
                                          -constraints.maxHeight *
                                          0.10; // move up 10%
                                      return Center(
                                        child: Transform.translate(
                                          offset: Offset(dx, dy),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Tank number:',
                                                style: TextStyle(
                                                  fontSize: 18 * scale,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 10 * scale),
                                              SizedBox(
                                                width:
                                                    (isPhone ? 300 : 420) *
                                                    scale,
                                                child: TextField(
                                                  controller: _tankController,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                    LengthLimitingTextInputFormatter(
                                                      3,
                                                    ),
                                                  ],
                                                  onChanged: _applyInput,
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText:
                                                            'Enter number',
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                ),
                                              ),
                                              SizedBox(height: 16 * scale),
                                              ElevatedButton(
                                                onPressed: _cancel,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.red[400],
                                                  foregroundColor: Colors.white,
                                                  minimumSize: Size(
                                                    140 * scale,
                                                    48 * scale,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          24 * scale,
                                                        ),
                                                  ),
                                                  textStyle: TextStyle(
                                                    fontSize: 16 * scale,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                child: const Text('Cancel'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Right panel
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 12 * scale : 28 * scale,
                              horizontal: 8 * scale,
                            ),
                            child: Column(
                              children: [
                                if (selectedDiverName != null)
                                  Text(
                                    selectedDiverName!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: (isPhone ? 30 : 42) * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (selectedTag != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 10 * scale),
                                    child: Text(
                                      selectedTag!.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: (isPhone ? 26 : 36) * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: EdgeInsets.only(top: 12 * scale),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Checked-In',
                                      style: TextStyle(
                                        fontSize: (isPhone ? 16 : 18) * scale,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.blueGrey[700],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Builder(
                                    builder: (_) {
                                      final data = checkedInDiversForContext;
                                      if (isOtherAggregated &&
                                          selectedSubDepartment == null) {
                                        return Center(
                                          child: Text(
                                            'Select a department to view.',
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 16) * scale,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        );
                                      }
                                      if (data.isEmpty) {
                                        return Center(
                                          child: Text(
                                            'No divers currently checked in.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 16) * scale,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        );
                                      }
                                      return ListView.builder(
                                        itemCount: data.length,
                                        itemBuilder: (_, i) {
                                          final m = data[i];
                                          final name = (m['name'] ?? '')
                                              .toString();
                                          final tag = m['tag'] as int?;
                                          final tankStr = tag == null
                                              ? '-'
                                              : tag.toString().padLeft(2, '0');
                                          final Color rowColor = i.isEven
                                              ? (Colors.blueGrey[50] ??
                                                    const Color(0x0D000000))
                                              : Colors.transparent;
                                          return Container(
                                            margin: EdgeInsets.symmetric(
                                              vertical: 3 * scale,
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8 * scale,
                                              vertical: 6 * scale,
                                            ),
                                            decoration: BoxDecoration(
                                              color: rowColor,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    8 * scale,
                                                  ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          (isPhone ? 14 : 16) *
                                                          scale,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  'Tank $tankStr',
                                                  style: TextStyle(
                                                    fontSize:
                                                        (isPhone ? 14 : 16) *
                                                        scale,
                                                    color: Colors.blueGrey[700],
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: (isPhone ? 160 : 200) * scale,
                                  height: (isPhone ? 60 : 70) * scale,
                                  child: ElevatedButton(
                                    onPressed:
                                        (selectedDiver != null &&
                                            (!isOtherAggregated ||
                                                selectedSubDepartment != null))
                                        ? _confirm
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          36 * scale,
                                        ),
                                      ),
                                      textStyle: TextStyle(
                                        fontSize: (isPhone ? 20 : 22) * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    child: const Text('Confirm'),
                                  ),
                                ),
                              ],
                            ),
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
