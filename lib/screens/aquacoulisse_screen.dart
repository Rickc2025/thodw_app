import 'dart:async';
import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/navigation.dart';
import '../services/data_service.dart';
import '../widgets/top_alert.dart';
import 'history_page.dart';
import 'operator_screen.dart';

class AquacoulisseScreen extends StatefulWidget {
  final String? department; // optional; null when coming from Home
  const AquacoulisseScreen({super.key, this.department});

  @override
  State<AquacoulisseScreen> createState() => _AquacoulisseScreenState();
}

class _AquacoulisseScreenState extends State<AquacoulisseScreen> {
  int currentlyIn = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goToOperator(String color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OperatorScreen(
          department: widget.department ?? "Deck Operator",
          aquacoulisse: color,
        ),
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

  @override
  Widget build(BuildContext context) {
    final colors = ["BLUE", "GREEN", "RED", "WHITE"];
    final topPad = MediaQuery.of(context).padding.top;
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
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.department ?? "Deck Operator",
                  style: TextStyle(
                    fontSize: sf(context, 34),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: sf(context, 8)),
                Text(
                  "Choose the AQUACOULISSE:",
                  style: TextStyle(
                    fontSize: sf(context, 26),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: sf(context, 30)),
                Wrap(
                  spacing: sf(context, 28),
                  runSpacing: sf(context, 22),
                  alignment: WrapAlignment.center,
                  children: [
                    for (final c in colors)
                      ElevatedButton(
                        onPressed: () => _goToOperator(c),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c == "WHITE"
                              ? Colors.grey
                              : c == "BLUE"
                              ? Colors.blue
                              : c == "GREEN"
                              ? Colors.green
                              : Colors.red,
                          foregroundColor: c == "WHITE"
                              ? Colors.black
                              : Colors.white,
                          minimumSize: Size(sf(context, 150), sf(context, 70)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              sf(context, 40),
                            ),
                          ),
                          textStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: sf(context, 24),
                          ),
                          elevation: 0,
                        ),
                        child: Text(c),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
