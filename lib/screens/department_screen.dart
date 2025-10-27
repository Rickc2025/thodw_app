import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../core/navigation.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'checkin_names_screen.dart';
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
        builder: (_) => CheckInNamesScreen(department: department),
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
                      for (final dep in departments)
                        ElevatedButton(
                          onPressed: () => _openNext(dep),
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
                          child: Text(dep),
                        ),
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
