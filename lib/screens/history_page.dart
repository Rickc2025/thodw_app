import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/utils.dart';
import '../services/data_service.dart';
import '../utils/exporter/exporter.dart';
import '../widgets/top_alert.dart';
import 'change_tag_screen.dart';

class HistoryPage extends StatefulWidget {
  final String selectedColor;
  const HistoryPage({super.key, required this.selectedColor});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Box logsBox;
  late Box checkinsBox;
  late Box diversBox;
  late String tab; // "CHECKED-IN" or color or "ALL"
  final List<String> tabs = [
    "CHECKED-IN",
    "BLUE",
    "GREEN",
    "RED",
    "WHITE",
    "ALL",
  ];
  int currentlyIn = 0;
  Timer? _timer;
  late StreamSubscription<BoxEvent> _logsSub;

  @override
  void initState() {
    super.initState();
    logsBox = Hive.box('logs');
    checkinsBox = Hive.box('checkins');
    diversBox = Hive.box('divers');
    final initial = widget.selectedColor.toUpperCase();
    tab = tabs.contains(initial) ? initial : "ALL";
    _updateCounts();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCounts());
    _logsSub = logsBox.watch().listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _updateCounts() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logsSub.cancel();
    super.dispose();
  }

  List<Map> _logsForTab(String filterTab) {
    final raw = logsBox.get('logsList', defaultValue: <Map>[]);
    final List<Map> allNewestFirst = List<Map>.from(raw).reversed.toList();

    final Map<String, Map> latestEventByKey = {};
    final Map<String, String> latestInDtByKey = {};
    for (final log in allNewestFirst) {
      final key = "${log['name']}|${log['tag']}";
      latestEventByKey.putIfAbsent(key, () => log);
      if ((log['status'] ?? '') == 'IN' && !latestInDtByKey.containsKey(key)) {
        latestInDtByKey[key] = (log['datetime'] ?? '').toString();
      }
    }
    final Set<String> keysCurrentlyIn = latestEventByKey.entries
        .where((e) => (e.value['status'] ?? '') == 'IN')
        .map((e) => e.key)
        .toSet();

    List<Map> logsList = List<Map>.from(allNewestFirst);
    if (filterTab != "ALL" && filterTab != "CHECKED-IN") {
      logsList = logsList
          .where(
            (log) =>
                (log['aquacoulisse'] ?? '').toString().toUpperCase() ==
                filterTab,
          )
          .toList();
    }

    final Map<String, Map> lastIN = {};
    for (int i = logsList.length - 1; i >= 0; i--) {
      final log = logsList[i];
      final key = "${log['name']}|${log['tag']}";
      if (log['status'] == 'IN') {
        lastIN[key] = log;
      } else if (log['status'] == 'OUT') {
        if (lastIN.containsKey(key)) {
          try {
            final inTime = DateTime.parse(lastIN[key]!['datetime']);
            final outTime = DateTime.parse(log['datetime']);
            if (outTime.isAfter(inTime)) {
              log['diveDuration'] = _formatDuration(outTime.difference(inTime));
              lastIN.remove(key);
            }
          } catch (_) {}
        }
      }
    }

    for (final log in logsList) {
      final key = "${log['name']}|${log['tag']}";
      final dt = (log['datetime'] ?? '').toString();
      final isCurrIn =
          (log['status'] == 'IN') &&
          keysCurrentlyIn.contains(key) &&
          latestInDtByKey[key] == dt;
      log['_isCurrentlyIn'] = isCurrIn;
    }

    logsList.sort((a, b) {
      final ai = (a['_isCurrentlyIn'] ?? false) ? 1 : 0;
      final bi = (b['_isCurrentlyIn'] ?? false) ? 1 : 0;
      if (ai != bi) return bi - ai;
      final ad = DateTime.tryParse(a['datetime'] ?? '') ?? DateTime(1970);
      final bd = DateTime.tryParse(b['datetime'] ?? '') ?? DateTime(1970);
      return bd.compareTo(ad);
    });

    return logsList;
  }

  List<Map> getLogsFiltered() => _logsForTab(tab);

  List<Map<String, dynamic>> getCheckedInList() {
    final box = checkinsBox;
    final List<Map<String, dynamic>> arr = [];
    for (final key in box.keys) {
      final data = (box.get(key) ?? {}) as Map;
      if ((data['checkedIn'] ?? false) == true) {
        final name = key.toString();
        arr.add({
          'name': name,
          'tag': data['tag'],
          'timestamp': data['timestamp'],
          'waterIn': diverIsInWater(name),
          'department': _departmentFor(name),
        });
      }
    }
    arr.sort(
      (a, b) => (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      ),
    );
    return arr;
  }

  String? _departmentFor(String name) {
    final list = List<Map>.from(
      diversBox.get('diversList', defaultValue: <Map>[]),
    );
    for (final d in list) {
      if ((d['name'] ?? '') == name) return d['department'];
    }
    return null;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final sh = h > 0 ? "${h}h" : "";
    final sm = m > 0 ? "${m}min" : (h == 0 ? "0min" : "");
    return "$sh$sm".trim();
  }

  Color? _tabColor(String t) {
    switch (t) {
      case "CHECKED-IN":
        return Colors.teal[400];
      case "BLUE":
        return Colors.blue[300];
      case "GREEN":
        return Colors.green[400];
      case "RED":
        return Colors.red[400];
      case "WHITE":
        return Colors.grey[400];
      case "ALL":
        return Colors.black54;
      default:
        return Colors.grey[200];
    }
  }

  Color _tabTextColor(String t, bool selected) {
    if (!selected) return Colors.black;
    if (t == "WHITE") return Colors.black;
    return Colors.white;
  }

  Widget _tabButton(String t) {
    final selected = tab == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => tab = t),
        child: Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? _tabColor(t) : Colors.grey[200],
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? (_tabColor(t) ?? Colors.grey) : Colors.grey,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            t,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _tabTextColor(t, selected),
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  String _timestampBase() {
    final now = DateTime.now();
    return "dive_log_${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _exportCSV() async {
    final logs = getLogsFiltered();
    final buffer = StringBuffer();
    buffer.writeln(
      "Name,Status,Tag,Datetime,Aquacoulisse,DiveDuration (if OUT)",
    );
    for (final log in logs) {
      final name = _csvSafe(log['name']);
      final status = _csvSafe(log['status']);
      final tag = _csvSafe(log['tag']?.toString());
      final dt = _csvSafe(log['datetime']);
      final aq = _csvSafe(log['aquacoulisse']);
      final dd = _csvSafe(log['diveDuration']);
      buffer.writeln('$name,$status,$tag,$dt,$aq,$dd');
    }
    await Exporter.saveCsv(_timestampBase(), buffer.toString());
  }

  Future<void> _exportXlsXml() async {
    final sb = StringBuffer();
    sb.writeln(r'<?xml version="1.0"?>');
    sb.writeln(
      '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
      'xmlns:o="urn:schemas-microsoft-com:office:office" '
      'xmlns:x="urn:schemas-microsoft-com:office:excel" '
      'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
    );

    {
      final list = getCheckedInList();
      sb.writeln('<Worksheet ss:Name="Checked-in"><Table>');
      final headers = ["Name", "Tag", "Water", "Checked‑In at"];
      sb.write('<Row>');
      for (final h in headers) {
        sb.write('<Cell><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
      }
      sb.writeln('</Row>');

      for (final item in list) {
        final name = (item['name'] ?? '').toString();
        final tag = (item['tag'] ?? '').toString();
        final water = (item['waterIn'] ?? false) ? 'IN' : 'OUT';
        String dateStr = '';
        try {
          final dt = DateTime.parse(item['timestamp'] ?? "");
          dateStr =
              "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
              "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        } catch (_) {}
        final row = [name, tag, water, dateStr];
        sb.write('<Row>');
        for (final cell in row) {
          sb.write(
            '<Cell><Data ss:Type="String">${_xmlEscape(cell)}</Data></Cell>',
          );
        }
        sb.writeln('</Row>');
      }

      sb.writeln('</Table></Worksheet>');
    }

    void addLogsSheet(String sheetName, String filterTab) {
      final logs = _logsForTab(filterTab);
      sb.writeln('<Worksheet ss:Name="${_xmlEscape(sheetName)}"><Table>');

      final headers = [
        "Name",
        "Status",
        "Tag",
        "Datetime",
        "Aquacoulisse",
        "DiveDuration (if OUT)",
      ];
      sb.write('<Row>');
      for (final h in headers) {
        sb.write('<Cell><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
      }
      sb.writeln('</Row>');

      for (final log in logs) {
        final row = [
          (log['name'] ?? '').toString(),
          (log['status'] ?? '').toString(),
          (log['tag'] ?? '').toString(),
          (log['datetime'] ?? '').toString(),
          (log['aquacoulisse'] ?? '').toString(),
          (log['diveDuration'] ?? '').toString(),
        ];
        sb.write('<Row>');
        for (final cell in row) {
          sb.write(
            '<Cell><Data ss:Type="String">${_xmlEscape(cell)}</Data></Cell>',
          );
        }
        sb.writeln('</Row>');
      }
      sb.writeln('</Table></Worksheet>');
    }

    addLogsSheet('BLUE', 'BLUE');
    addLogsSheet('GREEN', 'GREEN');
    addLogsSheet('RED', 'RED');
    addLogsSheet('WHITE', 'WHITE');
    addLogsSheet('ALL', 'ALL');

    sb.writeln('</Workbook>');
    await Exporter.saveXls(_timestampBase(), sb.toString());
  }

  String _xmlEscape(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _csvSafe(dynamic v) {
    if (v == null) return "";
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  void _openChangeTag(String name) async {
    if (diverIsInWater(name)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Change tag after OUT.")));
      return;
    }
    final result = await Navigator.push<int?>(
      context,
      MaterialPageRoute(builder: (_) => ChangeTagScreen(diverName: name)),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Tag updated for $name to ${result.toString().padLeft(2, '0')}",
          ),
        ),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = getLogsFiltered();
    final checkedList = getCheckedInList();
    final isPhone = MediaQuery.of(context).size.width < 600;
    final scale = appScale(context);
    return Scaffold(
      body: Stack(
        children: [
          TopAlert(
            currentlyIn: currentlyIn,
            onTap: () => setState(() => tab = "ALL"),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 8 * scale : 24 * scale,
                vertical: isPhone ? 6 * scale : 16 * scale,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, size: 28 * scale),
                        onPressed: () => Navigator.pop(context),
                      ),
                      SizedBox(width: 12 * scale),
                      Text(
                        'Log',
                        style: TextStyle(
                          fontSize: 28 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'csv') _exportCSV();
                          if (val == 'xls') _exportXlsXml();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'csv',
                            child: Text('Export CSV & Share/Download'),
                          ),
                          PopupMenuItem(
                            value: 'xls',
                            child: Text('Export Excel (.xls) & Share/Download'),
                          ),
                        ],
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.black,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: null,
                          child: Text(
                            "Export",
                            style: TextStyle(fontSize: 16 * scale),
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      IconButton(
                        icon: Icon(Icons.refresh, size: 24 * scale),
                        onPressed: () => setState(() {}),
                      ),
                    ],
                  ),
                  SizedBox(height: 10 * scale),
                  Row(children: [for (final t in tabs) _tabButton(t)]),
                  SizedBox(height: 12 * scale),
                  if (tab == "CHECKED-IN") ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 8 * scale,
                        horizontal: 8 * scale,
                      ),
                      color: Colors.grey[100],
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Name",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Tag",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Water",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Checked‑In at",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.black54),
                    Expanded(
                      child: checkedList.isEmpty
                          ? Center(
                              child: Text(
                                "No divers checked in.",
                                style: TextStyle(
                                  fontSize: 18 * scale,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: checkedList.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final item = checkedList[i];
                                final name = item['name'] as String;
                                final tag = item['tag'];
                                final waterIn = item['waterIn'] as bool;
                                DateTime? dt;
                                try {
                                  dt = DateTime.parse(item['timestamp'] ?? "");
                                } catch (_) {}
                                final dateStr = dt == null
                                    ? ""
                                    : "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
                                          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                                return InkWell(
                                  onTap: () => _openChangeTag(name),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 8 * scale,
                                      horizontal: 8 * scale,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 17) * scale,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            (tag ?? '').toString().padLeft(
                                              2,
                                              '0',
                                            ),
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 17) * scale,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            waterIn ? "IN" : "OUT",
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 17) * scale,
                                              color: waterIn
                                                  ? Colors.orange[800]
                                                  : Colors.black,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 14 : 17) * scale,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 8 * scale,
                        horizontal: 8 * scale,
                      ),
                      color: Colors.grey[100],
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Name:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Status:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Tag:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Date and Time:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Dive duration:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Aquacoulisse:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.black54),
                    Expanded(
                      child: logs.isEmpty
                          ? Center(
                              child: Text(
                                "No logs yet.",
                                style: TextStyle(
                                  fontSize: 18 * scale,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: logs.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final log = logs[idx];
                                DateTime? dt;
                                try {
                                  dt = DateTime.parse(log['datetime'] ?? "");
                                } catch (_) {}
                                final dateStr = dt == null
                                    ? ""
                                    : "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
                                          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                                final status = (log['status'] ?? '').toString();
                                final bool isCurrIn =
                                    (log['_isCurrentlyIn'] ?? false) == true;
                                final statusStyle = TextStyle(
                                  fontSize: (isPhone ? 14 : 17) * scale,
                                  color: status == 'IN' && isCurrIn
                                      ? Colors.orange[800]
                                      : Colors.black,
                                  fontWeight: status == 'IN' && isCurrIn
                                      ? FontWeight.w700
                                      : null,
                                );
                                final diveDur =
                                    (status == 'OUT' &&
                                        log['diveDuration'] != null)
                                    ? log['diveDuration']
                                    : "";
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 8 * scale,
                                    horizontal: 8 * scale,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          log['name'] ?? "",
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(status, style: statusStyle),
                                      ),
                                      Expanded(
                                        child: Text(
                                          (log['tag'] ?? '').toString(),
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          diveDur,
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          (log['aquacoulisse'] ?? '')
                                              .toString()
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
