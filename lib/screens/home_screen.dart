import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'aquacoulisse_screen.dart';
import 'department_screen.dart';
import 'history_page.dart';
import 'settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentlyIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
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

  void _startFlow(FlowMode flow) {
    if (flow == FlowMode.operator) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AquacoulisseScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DepartmentScreen(flowMode: FlowMode.checkIn),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn, onTap: _openLog),
          // Bottom-left static updated timestamp (single line)
          Positioned(
            left: 12 * scale,
            bottom: 12 * scale,
            child: Builder(
              builder: (_) {
                // User requested only the following static timestamp line
                const text = 'Updated: 2025-11-10 at 11:54 PM';
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * scale,
                    vertical: 6 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(6 * scale),
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 11.5 * scale,
                      color: Colors.black.withOpacity(0.65),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: topPad + 6 * scale,
            right: 12 * scale,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
                padding: EdgeInsets.symmetric(
                  horizontal: 20 * scale,
                  vertical: 10 * scale,
                ),
                textStyle: TextStyle(
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _openLog,
              child: const Text("  Log  "),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Select mode:",
                  style: TextStyle(
                    fontSize: 40 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 28 * scale),
                Wrap(
                  spacing: 28 * scale,
                  runSpacing: 20 * scale,
                  children: [
                    ElevatedButton(
                      onPressed: () => _startFlow(FlowMode.checkIn),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: Size(260 * scale, 90 * scale),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40 * scale),
                        ),
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 26 * scale,
                        ),
                      ),
                      child: const Text("Check In"),
                    ),
                    ElevatedButton(
                      onPressed: () => _startFlow(FlowMode.operator),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: Size(260 * scale, 90 * scale),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40 * scale),
                        ),
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 26 * scale,
                        ),
                      ),
                      child: const Text("Deck Operator"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32 * scale,
            right: 32 * scale,
            child: IconButton(
              tooltip: "Settings",
              icon: Icon(Icons.settings, size: 40 * scale),
              onPressed: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}
