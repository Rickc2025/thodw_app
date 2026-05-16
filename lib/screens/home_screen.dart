import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../services/auth_service.dart';
import '../services/state_cache.dart';
import '../services/user_context.dart';
import '../widgets/top_alert.dart';
import 'department_screen.dart';
import 'history_page.dart';
import 'login_screen.dart';
import 'settings_page.dart';
import 'operator_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentlyIn = 0;
  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _logsSub;

  @override
  void initState() {
    super.initState();
    _tick();
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen((_) => _tick());
    _logsSub = FirebaseFirestore.instance
        .collection('logs')
        .snapshots()
        .listen((_) => _tick());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final c = StateCache.currentlyIn();
    if (mounted) setState(() => currentlyIn = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _checkinsSub?.cancel();
    _logsSub?.cancel();
    super.dispose();
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistoryPage(selectedColor: "IN WATER"),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
        ],
      ),
    );

    if (confirm == true) {
      UserContext.clear();
      await AuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _startFlow(FlowMode flow) {
    if (flow == FlowMode.operator) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OperatorScreen()),
      );
    } else if (flow == FlowMode.showDeck) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OperatorScreen(showDeckMode: true),
        ),
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
                if ((UserContext.displayName ?? '').trim().isNotEmpty) ...[
                  Text(
                    'Welcome, ${UserContext.displayName!}',
                    style: TextStyle(
                      fontSize: 24 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 10 * scale),
                ],
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
                    ElevatedButton(
                      onPressed: () => _startFlow(FlowMode.showDeck),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[700],
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
                      child: const Text("Show Deck"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32 * scale,
            left: 32 * scale,
            child: IconButton(
              tooltip: 'Logout',
              icon: Icon(Icons.logout, size: 40 * scale),
              onPressed: _confirmLogout,
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
