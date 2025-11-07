import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../core/navigation.dart';
import '../core/utils.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'history_page.dart';

class CheckInNamesScreen extends StatefulWidget {
  final String department;
  const CheckInNamesScreen({super.key, required this.department});

  @override
  State<CheckInNamesScreen> createState() => _CheckInNamesScreenState();
}

class _CheckInNamesScreenState extends State<CheckInNamesScreen> {
  late Box diversBox;
  late Box checkinsBox;

  List<Map> divers = [];
  String selectedTeam = teams.first;
  String? selectedDiver;
  int? selectedTag;
  final TextEditingController _tankController = TextEditingController();
  static const int _maxTank = 999;

  int currentlyIn = 0;
  Timer? _timer;

  bool get isShowDivers => widget.department == 'SHOW DIVERS';
  bool get isOtherAggregated => widget.department == 'OTHER';
  String? selectedSubDepartment; // drill-down for OTHER

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tankController.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    if (isOtherAggregated) {
      if (selectedSubDepartment != null) {
        divers = list
            .where((d) => d['department'] == selectedSubDepartment)
            .toList();
      } else {
        divers = [];
      }
    } else {
      divers = list.where((d) => d['department'] == widget.department).toList();
    }
    setState(() {});
  }

  Map<String, int> _otherSubDepartmentCounts() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    final Map<String, int> counts = {};
    for (final d in list) {
      final dep = (d['department'] ?? '').toString();
      if (dep.isEmpty) continue;
      if (dep == 'SHOW DIVERS' || dep == 'DAY CREW') continue;
      counts[dep] = (counts[dep] ?? 0) + 1;
    }
    return counts;
  }

  void _applyInput(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    String trimmed = digits.replaceFirst(RegExp(r'^0+'), '');
    if (trimmed.isEmpty) {
      setState(() {
        _tankController.text = '';
        selectedTag = null;
      });
      return;
    }
    if (trimmed.length > 3) trimmed = trimmed.substring(0, 3);
    final val = int.tryParse(trimmed);
    setState(() {
      _tankController.text = trimmed;
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _cancel() {
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      _tankController.clear();
    });
  }

  void _confirm() {
    if (selectedDiver == null || selectedTag == null) {
      _snack('Please enter a tank number.');
      return;
    }
    if (isCheckedIn(selectedDiver!)) {
      _snack('Already checked in. Change tank from Log → Checked‑In.');
      return;
    }
    if (tankInUse(selectedTag!)) {
      _snack(
        'Tank ${selectedTag!.toString().padLeft(2, '0')} is already in use.',
      );
      return;
    }
    checkinsBox.put(selectedDiver!, {
      'checkedIn': true,
      'tag': selectedTag!,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _snack('Checked in!');
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
                          final counts = _otherSubDepartmentCounts();
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
                                                        person['name'];
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

                              if (selectedDiver != null) ...[
                                // Center vertically within left panel
                                Expanded(
                                  child: Center(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return Transform.translate(
                                          // Shift further right (20%) and up (10% of height)
                                          offset: Offset(
                                            constraints.maxWidth * 0.25,
                                            -constraints.maxHeight * 0.10,
                                          ),
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
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 12 * scale : 28 * scale,
                              horizontal: 8 * scale,
                            ),
                            child: Column(
                              children: [
                                if (selectedDiver != null)
                                  Text(
                                    selectedDiver!,
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
                                const Spacer(),
                                SizedBox(
                                  width: (isPhone ? 160 : 200) * scale,
                                  height: (isPhone ? 60 : 70) * scale,
                                  child: ElevatedButton(
                                    onPressed:
                                        (selectedDiver != null &&
                                            selectedTag != null &&
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

/*
  List<Map> get displayedDivers {
    if (isShowDivers) {
      return divers.where((d) => d['team'] == selectedTeam).toList();
    }
    return divers;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _cancel() {
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      tagPage = 0;
      _tankController.clear();
    });
  }

  void _confirm() {
    if (selectedDiver == null || selectedTag == null) {
      _snack("Please enter a tank number.");
      return;
    }
    if (isCheckedIn(selectedDiver!)) {
      _snack("Already checked in. Change tank from Log → Checked‑In.");
      return;
    }
    if (tankInUse(selectedTag!)) {
      _snack(
        "Tank ${selectedTag!.toString().padLeft(2, '0')} is already in use.",
      );
      return;
    }
    checkinsBox.put(selectedDiver!, {
      'checkedIn': true,
      'tag': selectedTag!,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _snack("Checked in!");
    _cancel();
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistoryPage(selectedColor: "ALL"),
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
                        tooltip: "Home",
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
                              ? "OTHER DEPARTMENTS - SELECT DEPARTMENT"
                              : "${selectedSubDepartment} - CHECK IN")
                        : "${widget.department} - CHECK IN",
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
                                tagPage = 0;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedTeam == t
                                  ? teamColor(t)
                                  : Colors.grey[100],
                              foregroundColor: selectedTeam == t
                                  ? (t == "WHITE" ? Colors.black : Colors.white)
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
                            child: Text("$t TEAM"),
                          ),
                      ],
                    ),

                  if (isShowDivers) SizedBox(height: 8 * scale),

                  if (isOtherAggregated && selectedSubDepartment == null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8 * scale),
                      child: Builder(
                        builder: (_) {
                          final counts = _otherSubDepartmentCounts();
                          final deps = counts.keys.toList()..sort();
                          if (deps.isEmpty) {
                            return Center(
                              child: Text(
                                "No departments found.",
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
                                      tagPage = 0;
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
                                        ? "$dep (${counts[dep]})"
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
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              if (isOtherAggregated &&
                                  selectedSubDepartment == null)
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      "Select a department above.",
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
                                            "No names found.\nAdd in Settings.",
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
                                                              "WHITE")
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
                                                        person['name'];
                                                    selectedTag = null;
                                                    tagPage = 0;
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

                              // remove duplicated old layout block below
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 12 * scale : 28 * scale,
                              horizontal: 8 * scale,
                            ),
                            child: Column(
                              children: [
                                if (selectedDiver != null)
                                  Text(
                                    selectedDiver!,
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
                                const Spacer(),
                                SizedBox(
                                  width: (isPhone ? 160 : 200) * scale,
                                  height: (isPhone ? 60 : 70) * scale,
                                  child: ElevatedButton(
                                    onPressed:
                                        (selectedDiver != null &&
                                            selectedTag != null &&
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
                                    child: const Text("Confirm"),
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
*/
