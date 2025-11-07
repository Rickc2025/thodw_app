import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'package:hive/hive.dart';
import '../core/utils.dart';
import '../core/navigation.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'checkin_names_screen2.dart';
import 'history_page.dart';
import 'settings_page.dart';

class DepartmentScreen extends StatefulWidget {
  final FlowMode flowMode;
  const DepartmentScreen({super.key, required this.flowMode});

  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen> {
  int currentlyIn = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
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

  void _openNext(String department) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInNamesScreen2(department: department),
      ),
    );
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistoryPage(selectedColor: "ALL"),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    const modeTitle = "Check In";
    // Only list departments that actually have at least one diver configured.
    final stored = Hive.box('divers').get('diversList', defaultValue: <Map>[]);
    final diverList = List<Map>.from(stored);
    final Set<String> depsWithDivers = {
      for (final d in diverList)
        if (((d['name'] ?? '').toString().isNotEmpty) &&
            (d['department'] ?? '') != '')
          (d['department'] ?? '').toString(),
    };
    // Group any non core departments (not SHOW DIVERS / DAY CREW) under OTHER

    final bool hasShowDivers = depsWithDivers.contains("SHOW DIVERS");
    final bool hasDayCrew = depsWithDivers.contains("DAY CREW");
    // Treat any department that isn't SHOW DIVERS or DAY CREW as OTHER
    final bool hasOther = depsWithDivers.any(
      (d) => d != 'SHOW DIVERS' && d != 'DAY CREW',
    );
    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn, onTap: _openLog),
          Positioned(
            top: topPad + sf(context, 6),
            left: sf(context, 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, size: sf(context, 28)),
                  onPressed: () => Navigator.pop(context),
                ),
                SizedBox(width: sf(context, 4)),
                IconButton(
                  tooltip: "Home",
                  icon: Icon(Icons.home_outlined, size: sf(context, 26)),
                  onPressed: () => goHome(context),
                ),
              ],
            ),
          ),
          Positioned(
            top: topPad + sf(context, 6),
            right: sf(context, 12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
                padding: EdgeInsets.symmetric(
                  horizontal: sf(context, 20),
                  vertical: sf(context, 10),
                ),
                textStyle: TextStyle(
                  fontSize: sf(context, 18),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _openLog,
              child: const Text("  Log  "),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: sf(context, 70)),
                  Text(
                    modeTitle,
                    style: TextStyle(
                      fontSize: sf(context, 34),
                      fontWeight: FontWeight.w700,
                      color: Colors.blueGrey[700],
                    ),
                  ),
                  SizedBox(height: sf(context, 10)),
                  Text(
                    'Choose the department:',
                    style: TextStyle(
                      fontSize: sf(context, 40),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: sf(context, 28)),
                  Wrap(
                    spacing: sf(context, 32),
                    runSpacing: sf(context, 24),
                    alignment: WrapAlignment.center,
                    children: [
                      if (!hasShowDivers && !hasDayCrew && !hasOther)
                        Padding(
                          padding: EdgeInsets.all(sf(context, 12)),
                          child: Text(
                            'No departments available yet.\nAdd divers first in Settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: sf(context, 22),
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else ...[
                        if (hasShowDivers)
                          ElevatedButton(
                            onPressed: () => _openNext("SHOW DIVERS"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: Size(
                                sf(context, 260),
                                sf(context, 70),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  sf(context, 40),
                                ),
                              ),
                              textStyle: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: sf(context, 22),
                              ),
                              elevation: 0,
                            ),
                            child: const Text("SHOW DIVERS"),
                          ),
                        if (hasDayCrew)
                          ElevatedButton(
                            onPressed: () => _openNext("DAY CREW"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: Size(
                                sf(context, 260),
                                sf(context, 70),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  sf(context, 40),
                                ),
                              ),
                              textStyle: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: sf(context, 22),
                              ),
                              elevation: 0,
                            ),
                            child: const Text("DAY CREW"),
                          ),
                        if (hasOther)
                          ElevatedButton(
                            onPressed: () => _openNext("OTHER"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: Size(
                                sf(context, 260),
                                sf(context, 70),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  sf(context, 40),
                                ),
                              ),
                              textStyle: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: sf(context, 22),
                              ),
                              elevation: 0,
                            ),
                            child: const Text("OTHER"),
                          ),
                      ],
                    ],
                  ),
                  SizedBox(height: sf(context, 60)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: sf(context, 32),
            right: sf(context, 32),
            child: IconButton(
              tooltip: "Settings",
              icon: Icon(Icons.settings, size: sf(context, 40)),
              onPressed: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}
