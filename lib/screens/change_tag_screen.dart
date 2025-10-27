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
  int tagPage = 0;
  int? selectedTag;
  static const int tagsPerPage = 20;

  List<int> get currentTagPage {
    final start = tagPage * tagsPerPage + 1;
    return List.generate(
      tagsPerPage,
      (i) => start + i,
    ).where((n) => n <= 100).toList();
  }

  int get maxTagPage => (100 / tagsPerPage).ceil();

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _confirm() {
    if (selectedTag == null) {
      _snack("Please select a tag number.");
      return;
    }
    if (tagInUse(selectedTag!, exceptName: widget.diverName)) {
      _snack(
        "Tag ${selectedTag!.toString().padLeft(2, '0')} is already in use.",
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

    final crossAxisCount = isPhone ? 2 : 4;
    final gridSpacing = 12.0 * scale;
    final childAspect = isPhone ? 1.8 : 2.45;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Change Tag"),
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
                  "Tag number:",
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 16 * scale),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < maxTagPage; i++)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4 * scale,
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  tagPage = i;
                                  selectedTag = null;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tagPage == i
                                    ? Colors.blue
                                    : Colors.grey[100],
                                foregroundColor: tagPage == i
                                    ? Colors.white
                                    : Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    18 * scale,
                                  ),
                                ),
                                elevation: 0,
                                minimumSize: Size(90 * scale, 48 * scale),
                                textStyle: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              child: Text(
                                "${(i * 20 + 1).toString().padLeft(2, '0')}-${((i + 1) * 20).clamp(1, 100).toString().padLeft(2, '0')}",
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),
            Expanded(
              child: GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: gridSpacing,
                crossAxisSpacing: gridSpacing,
                childAspectRatio: childAspect,
                children: [
                  for (final t in currentTagPage)
                    Builder(
                      builder: (_) {
                        final inUse = tagInUse(t, exceptName: widget.diverName);
                        final bool isSel = selectedTag == t;
                        final Color bg = isSel
                            ? Colors.black
                            : (inUse ? Colors.grey[400]! : Colors.grey[300]!);
                        final Color fg = isSel ? Colors.white : Colors.black;
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: bg,
                            foregroundColor: fg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            elevation: 0,
                          ),
                          onPressed: inUse
                              ? () => _snack(
                                  "Tag ${t.toString().padLeft(2, '0')} is already in use.",
                                )
                              : () => setState(() => selectedTag = t),
                          child: Text(t.toString().padLeft(2, '0')),
                        );
                      },
                    ),
                ],
              ),
            ),
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
