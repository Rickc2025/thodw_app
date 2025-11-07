import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../services/data_service.dart';
import 'package:hive/hive.dart';

class ChangeTagScreen extends StatefulWidget {
  final String diverName;
  const ChangeTagScreen({super.key, required this.diverName});

  @override
  State<ChangeTagScreen> createState() => _ChangeTagScreenState();
}

class _ChangeTagScreenState extends State<ChangeTagScreen> {
  int? selectedTag;
  final TextEditingController _tankController = TextEditingController();

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _confirm() {
    if (selectedTag == null) {
      _snack("Please enter a tank number.");
      return;
    }
    if (tankInUse(selectedTag!, exceptName: widget.diverName)) {
      _snack(
        "Tank ${selectedTag!.toString().padLeft(2, '0')} is already in use.",
      );
      return;
    }
    final box = Hive.box('checkins');
    final data = (box.get(widget.diverName) ?? {}) as Map;
    if ((data['checkedIn'] ?? false) != true) {
      _snack("Diver is not checked in.");
      return;
    }
    data['tag'] = selectedTag!;
    box.put(widget.diverName, data);
    Navigator.pop<int>(context, selectedTag);
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Change Tank"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(12 * scale),
        child: Row(
          children: [
            // Left: centered vertical input group
            Expanded(
              flex: 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dx = constraints.maxWidth * 0.25;
                  final dy = -constraints.maxHeight * 0.10;
                  return Center(
                    child: Transform.translate(
                      offset: Offset(dx, dy),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Tank number:",
                            style: TextStyle(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 10 * scale),
                          SizedBox(
                            width: (isPhone ? 300 : 420) * scale,
                            child: TextField(
                              controller: _tankController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              onChanged: (val) {
                                final n = int.tryParse(val);
                                setState(() {
                                  selectedTag = (n == null || n < 1)
                                      ? null
                                      : n.clamp(1, 999);
                                });
                              },
                              decoration: const InputDecoration(
                                hintText: 'Enter number',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(height: 16 * scale),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[400],
                              foregroundColor: Colors.white,
                              minimumSize: Size(140 * scale, 48 * scale),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24 * scale),
                              ),
                              textStyle: TextStyle(
                                fontSize: 16 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: const Text("Cancel"),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Right: diver name and confirm button at bottom
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Text(
                    widget.diverName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (isPhone ? 30 : 42) * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (selectedTag != null)
                    Padding(
                      padding: EdgeInsets.only(top: 12 * scale),
                      child: Text(
                        selectedTag!.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: (isPhone ? 26 : 36) * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(bottom: 40 * scale),
                    child: SizedBox(
                      width: (isPhone ? 160 : 200) * scale,
                      height: (isPhone ? 60 : 70) * scale,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(36 * scale),
                          ),
                          textStyle: TextStyle(
                            fontSize: (isPhone ? 20 : 22) * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: const Text("Confirm"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
