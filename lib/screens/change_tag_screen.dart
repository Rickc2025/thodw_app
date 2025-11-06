import 'package:flutter/material.dart';

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

    // grid variables removed; numeric input replaces grid selection

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.diverName,
              style: TextStyle(
                fontSize: (isPhone ? 26 : 32) * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10 * scale),
            Row(
              children: [
                Text(
                  "Tank number:",
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 16 * scale),
                SizedBox(
                  width: 160 * scale,
                  child: TextField(
                    controller: _tankController,
                    keyboardType: TextInputType.number,
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
              ],
            ),
            SizedBox(height: 8 * scale),
            const Spacer(),
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}
