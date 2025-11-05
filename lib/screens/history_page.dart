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
  // When false, hide tabs and show full history (ALL) view.
  final bool showTabs;
  const HistoryPage({
    super.key,
    required this.selectedColor,
    this.showTabs = true,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Box logsBox;
  late Box checkinsBox;
  late Box diversBox;
  late String tab; // "CHECKED-IN" or color or "ALL" or "IN WATER"
  // Visible tabs (no ALL); IN WATER replaces old ALL quick filter.
  final List<String> tabs = const [
    "CHECKED-IN",
    "BLUE",
    "GREEN",
    "RED",
    "WHITE",
    "IN WATER",
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
    // Keep support for internal "ALL" selection even if it's not a visible tab.
    tab = (tabs.contains(initial) || initial == "ALL") ? initial : "ALL";
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

  DateTime? _tryParseDT(dynamic s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s.toString());
    } catch (_) {
      return null;
    }
  }

  // Build sessions: one row per dive with IN and (optional) OUT.
  List<Map<String, dynamic>> _sessionsForTab(String filterTab) {
    final raw = logsBox.get('logsList', defaultValue: <Map>[]);
    // Work with chronological order (oldest -> newest) to pair correctly.
    final List<Map> chronological = List<Map>.from(raw);

    // Filter by aquacoulisse if needed (will match IN or OUT aquacoulisse).
    bool filterByAq =
        filterTab != "ALL" &&
        filterTab != "CHECKED-IN" &&
        filterTab != "IN WATER";

    // Build sessions per diver (ignore tag changes for pairing; store tag from IN).
    final Map<String, List<Map<String, dynamic>>> openStacks = {};
    final List<Map<String, dynamic>> sessions = [];

    for (final log in chronological) {
      final name = (log['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final status = (log['status'] ?? '').toString().toUpperCase();
      final dt = _tryParseDT(log['datetime']);
      if (dt == null) continue;

      if (status == 'IN') {
        final session = <String, dynamic>{
          'name': name,
          'tag': (log['tag'] ?? '').toString(),
          'datetimeIn': dt.toIso8601String(),
          'datetimeOut': null,
          'aquacoulisseIn': (log['aquacoulisse'] ?? '').toString(),
          'aquacoulisseOut': null,
          'diveDuration': '',
        };
        openStacks
            .putIfAbsent(name, () => <Map<String, dynamic>>[])
            .add(session);
        sessions.add(session);
      } else if (status == 'OUT') {
        final stack = openStacks[name];
        if (stack != null && stack.isNotEmpty) {
          // Pair with the most recent unmatched IN.
          final last = stack.removeLast();
          last['datetimeOut'] = dt.toIso8601String();
          last['aquacoulisseOut'] = (log['aquacoulisse'] ?? '').toString();
          final inDt = _tryParseDT(last['datetimeIn']);
          if (inDt != null && dt.isAfter(inDt)) {
            last['diveDuration'] = _formatDuration(dt.difference(inDt));
          }
        } else {
          // Orphan OUT without a prior IN; ignore for session building.
        }
      }
    }

    // Mark sessions that are currently in (no OUT and diver is in water).
    for (final s in sessions) {
      final bool currentlyIn = s['datetimeOut'] == null;
      s['_isCurrentlyIn'] = currentlyIn;
    }

    // Apply aquacoulisse filter (match either IN or OUT aquacoulisse).
    List<Map<String, dynamic>> filtered = filterByAq
        ? sessions.where((s) {
            final inAq = (s['aquacoulisseIn'] ?? '').toString().toUpperCase();
            final outAq = (s['aquacoulisseOut'] ?? '').toString().toUpperCase();
            return inAq == filterTab || outAq == filterTab;
          }).toList()
        : sessions;

    // IN WATER filter: only sessions with no OUT yet
    if (filterTab == "IN WATER") {
      filtered = filtered.where((s) => (s['datetimeOut'] == null)).toList();
    }

    // Sort: currently in first, then by In datetime desc.
    filtered.sort((a, b) {
      final ai = (a['_isCurrentlyIn'] ?? false) ? 1 : 0;
      final bi = (b['_isCurrentlyIn'] ?? false) ? 1 : 0;
      if (ai != bi) return bi - ai;
      final ad = _tryParseDT(a['datetimeIn']) ?? DateTime(1970);
      final bd = _tryParseDT(b['datetimeIn']) ?? DateTime(1970);
      return bd.compareTo(ad);
    });

    return filtered;
  }

  List<Map> getLogsFiltered() => _sessionsForTab(tab);

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
    final sessions = getLogsFiltered();
    final buffer = StringBuffer();
    buffer.writeln(
      "Name,Status,Tag,DateTime In,DateTime Out,Aquacoulisse In,Aquacoulisse Out,DiveDuration",
    );
    for (final s in sessions) {
      final name = _csvSafe(s['name']);
      final status = _csvSafe((s['datetimeOut'] == null) ? 'IN' : 'OUT');
      final tag = _csvSafe(s['tag']?.toString());
      final dtIn = _csvSafe(s['datetimeIn']);
      final dtOut = _csvSafe(s['datetimeOut']);
      final aqIn = _csvSafe(s['aquacoulisseIn']);
      final aqOut = _csvSafe(s['aquacoulisseOut']);
      final dd = _csvSafe(s['diveDuration']);
      buffer.writeln('$name,$status,$tag,$dtIn,$dtOut,$aqIn,$aqOut,$dd');
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
      final sessions = _sessionsForTab(filterTab);
      sb.writeln('<Worksheet ss:Name="${_xmlEscape(sheetName)}"><Table>');

      final headers = [
        "Name",
        "Status",
        "Tag",
        "DateTime In",
        "DateTime Out",
        "Aquacoulisse In",
        "Aquacoulisse Out",
        "DiveDuration",
      ];
      sb.write('<Row>');
      for (final h in headers) {
        sb.write('<Cell><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
      }
      sb.writeln('</Row>');

      for (final s in sessions) {
        final status = (s['datetimeOut'] == null) ? 'IN' : 'OUT';
        final row = [
          (s['name'] ?? '').toString(),
          status,
          (s['tag'] ?? '').toString(),
          (s['datetimeIn'] ?? '').toString(),
          (s['datetimeOut'] ?? '').toString(),
          (s['aquacoulisseIn'] ?? '').toString(),
          (s['aquacoulisseOut'] ?? '').toString(),
          (s['diveDuration'] ?? '').toString(),
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
            onTap: widget.showTabs
                ? () => setState(() => tab = "IN WATER")
                : null,
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
                  if (widget.showTabs)
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
                              "Date and Time In:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Date and Time Out:",
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
                            child: Text(
                              "Aquacoulisse In:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Aquacoulisse Out:",
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
                                final s = logs[idx];
                                DateTime? dtIn;
                                DateTime? dtOut;
                                try {
                                  dtIn = DateTime.parse(s['datetimeIn'] ?? "");
                                } catch (_) {}
                                try {
                                  dtOut = s['datetimeOut'] == null
                                      ? null
                                      : DateTime.parse(s['datetimeOut']);
                                } catch (_) {}
                                String dateStrIn = '';
                                String dateStrOut = '';
                                if (dtIn != null) {
                                  dateStrIn =
                                      "${dtIn.year}-${dtIn.month.toString().padLeft(2, '0')}-${dtIn.day.toString().padLeft(2, '0')} "
                                      "${dtIn.hour.toString().padLeft(2, '0')}:${dtIn.minute.toString().padLeft(2, '0')}";
                                }
                                if (dtOut != null) {
                                  dateStrOut =
                                      "${dtOut.year}-${dtOut.month.toString().padLeft(2, '0')}-${dtOut.day.toString().padLeft(2, '0')} "
                                      "${dtOut.hour.toString().padLeft(2, '0')}:${dtOut.minute.toString().padLeft(2, '0')}";
                                }
                                final bool isCurrIn =
                                    (s['_isCurrentlyIn'] ?? false) == true;
                                final inStyle = TextStyle(
                                  fontSize: (isPhone ? 14 : 17) * scale,
                                  color: isCurrIn
                                      ? Colors.orange[800]
                                      : Colors.black,
                                  fontWeight: isCurrIn ? FontWeight.w700 : null,
                                );
                                final statusText = isCurrIn ? 'IN' : 'OUT';
                                final statusStyle = TextStyle(
                                  fontSize: (isPhone ? 14 : 17) * scale,
                                  color: isCurrIn
                                      ? Colors.orange[800]
                                      : Colors.black,
                                  fontWeight: isCurrIn ? FontWeight.w700 : null,
                                );
                                final diveDur = (s['diveDuration'] ?? '')
                                    .toString();
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
                                          s['name'] ?? "",
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          statusText,
                                          style: statusStyle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          (s['tag'] ?? '').toString(),
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(dateStrIn, style: inStyle),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          dateStrOut,
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
                                        child: Text(
                                          (s['aquacoulisseIn'] ?? '')
                                              .toString()
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize:
                                                (isPhone ? 14 : 17) * scale,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          (s['aquacoulisseOut'] ?? '')
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
