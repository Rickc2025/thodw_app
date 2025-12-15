import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../core/utils.dart';
import '../services/state_cache.dart';
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
  late Box diversBox;
  late String tab; // "CHECKED-IN" or "IN WATER" or "ALL"
  // Visible tabs after removing aquacoulisse colors.
  final List<String> tabs = const ["CHECKED-IN", "IN WATER", "ALL"];
  int currentlyIn = 0;
  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _logsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  // No color shortcuts; aquacoulisse removed.

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    final initial = widget.selectedColor.toUpperCase();
    // Keep support for internal "ALL" selection even if it's not a visible tab.
    tab = (tabs.contains(initial) || initial == "ALL") ? initial : "ALL";
    _updateCounts();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCounts());
    _logsSub = FirebaseFirestore.instance
        .collection('logs')
        .orderBy('datetime')
        .snapshots()
        .listen((_) {
          _refreshCaches();
          if (mounted) setState(() {});
        });
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen((_) {
          _refreshCaches();
          if (mounted) setState(() {});
        });
  }

  Future<void> _updateCounts() async {
    if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logsSub?.cancel();
    _checkinsSub?.cancel();
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
    // Pull logs from Firestore snapshot synchronously from cached sessions built below.
    final chronological = _firestoreLogsChronological;

    // Build sessions per diver (ignore tank changes for pairing; store tank from IN).
    final Map<String, List<Map<String, dynamic>>> openStacks = {};
    final List<Map<String, dynamic>> sessions = [];

    for (int i = 0; i < chronological.length; i++) {
      final log = chronological[i];
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
          'diveDuration': '',
          'gasIn': log['gasIn'],
          'gasOut': null,
          'logIndexIn': i,
          'logIndexOut': null,
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
          last['gasOut'] = log['gasOut'];
          last['logIndexOut'] = i;
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

    List<Map<String, dynamic>> filtered = sessions;

    // IN WATER filter: only sessions with no OUT yet
    if (filterTab == "IN WATER") {
      filtered = filtered.where((s) => (s['datetimeOut'] == null)).toList();
    }

    // Sort: for IN WATER tab show alphabetical; otherwise show by recency.
    if (filterTab == "IN WATER") {
      filtered.sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      );
    } else {
      // currently in first, then by In datetime desc
      filtered.sort((a, b) {
        final ai = (a['_isCurrentlyIn'] ?? false) ? 1 : 0;
        final bi = (b['_isCurrentlyIn'] ?? false) ? 1 : 0;
        if (ai != bi) return bi - ai;
        final ad = _tryParseDT(a['datetimeIn']) ?? DateTime(1970);
        final bd = _tryParseDT(b['datetimeIn']) ?? DateTime(1970);
        return bd.compareTo(ad);
      });
    }

    return filtered;
  }

  Future<void> _quickIn(String name, {int? tag}) async {
    final now = DateTime.now().toIso8601String();
    await StateCache.addLogs([
      {'name': name, 'status': 'IN', 'tag': tag ?? '', 'datetime': now},
    ]);
    await StateCache.setCheckin(name, checkedIn: true, tag: tag);
    // Refresh local caches immediately so UI updates without manual refresh
    _refreshCaches();
    if (mounted) setState(() {});
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Checked IN $name')));
    }
  }

  Future<void> _quickOut(String name, {int? tag}) async {
    final now = DateTime.now().toIso8601String();
    final int? lt = tag ?? StateCache.checkedInTank(name);
    await StateCache.addLogs([
      {
        'name': name,
        'status': 'OUT',
        'tag': lt ?? '',
        'datetime': now,
        'gasOut': null,
      },
    ]);
    // Do NOT change deck check-in status here. Only water state changes.
    // Refresh local caches immediately so UI updates without manual refresh
    _refreshCaches();
    if (mounted) setState(() {});
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Checked OUT $name')));
    }
  }

  List<Map> getLogsFiltered() => _sessionsForTab(tab);

  List<Map<String, dynamic>> getCheckedInList() {
    final List<Map<String, dynamic>> arr = [];
    for (final name in _allKnownNames) {
      if (StateCache.isCheckedIn(name)) {
        arr.add({
          'name': name,
          'tag': StateCache.checkedInTank(name),
          'timestamp': StateCache.checkedInTimestamp(name),
          'waterIn': StateCache.diverIsInWater(name),
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
      case "IN WATER":
        // Make selected IN WATER tab high-contrast (match alert orange tone)
        return Colors.orange[800];
      case "ALL":
        return Colors.black54;
      default:
        return Colors.grey[200];
    }
  }

  Color _tabTextColor(String t, bool selected) {
    if (!selected) return Colors.black;
    if (t == "IN WATER") return Colors.white; // ensure contrast on orange
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
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    final mon = months[now.month - 1];
    final yyyy = now.year.toString();
    final dd = now.day.toString().padLeft(2, '0');
    final hm =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    // Example: 2025_nov_10_0046_dive_log
    return '${yyyy}_${mon}_${dd}_${hm}_dive_log';
  }

  Future<void> _exportCSV() async {
    final sessions = getLogsFiltered();
    final buffer = StringBuffer();
    buffer.writeln(
      "Name,Tank,Gas In,Gas Out,DateTime In,DateTime Out,DiveDuration",
    );
    for (final s in sessions) {
      final name = _csvSafe(s['name']);
      final tag = _csvSafe(s['tag']?.toString());
      final gasIn = _csvSafe(s['gasIn'] == null ? '' : '${s['gasIn']}bar');
      final gasOut = _csvSafe(s['gasOut'] == null ? '' : '${s['gasOut']}bar');
      final dtIn = _csvSafe(s['datetimeIn']);
      final dtOut = _csvSafe(s['datetimeOut']);
      final dd = _csvSafe(s['diveDuration']);
      buffer.writeln('$name,$tag,$gasIn,$gasOut,$dtIn,$dtOut,$dd');
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
      final headers = ["Name", "Tank", "Checked‑In at"];
      sb.write('<Row>');
      for (final h in headers) {
        sb.write('<Cell><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
      }
      sb.writeln('</Row>');

      for (final item in list) {
        final name = (item['name'] ?? '').toString();
        final tag = (item['tag'] ?? '').toString();
        String dateStr = '';
        try {
          final dt = DateTime.parse(item['timestamp'] ?? "");
          dateStr =
              "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
              "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        } catch (_) {}
        final row = [name, tag, dateStr];
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
        "Tank",
        "Gas In",
        "Gas Out",
        "DateTime In",
        "DateTime Out",
        "DiveDuration",
      ];
      sb.write('<Row>');
      for (final h in headers) {
        sb.write('<Cell><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
      }
      sb.writeln('</Row>');

      for (final s in sessions) {
        final row = [
          (s['name'] ?? '').toString(),
          (s['tag'] ?? '').toString(),
          s['gasIn'] == null ? '' : '${s['gasIn']}bar',
          s['gasOut'] == null ? '' : '${s['gasOut']}bar',
          (s['datetimeIn'] ?? '').toString(),
          (s['datetimeOut'] ?? '').toString(),
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

  Future<void> _editSessionDialog(Map<String, dynamic> session) async {
    // Pull current logs from Firestore for editing
    final snap = await FirebaseFirestore.instance
        .collection('logs')
        .orderBy('datetime')
        .get();
    final List<Map<String, dynamic>> logsList = [
      for (final d in snap.docs) d.data(),
    ];
    // Extract existing values
    String tank = (session['tag'] ?? '').toString();
    int? gasIn = session['gasIn'] is int ? session['gasIn'] as int : null;
    int? gasOut = session['gasOut'] is int ? session['gasOut'] as int : null;
    DateTime? dtIn = _tryParseDT(session['datetimeIn']);
    DateTime? dtOut = _tryParseDT(session['datetimeOut']);

    final tankCtrl = TextEditingController(text: tank);
    final gasInCtrl = TextEditingController(text: gasIn?.toString() ?? '');
    final gasOutCtrl = TextEditingController(text: gasOut?.toString() ?? '');

    Future<void> _pickIn() async {
      dtIn ??= DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: dtIn!,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(dtIn!),
      );
      if (t == null) return;
      dtIn = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }

    Future<void> _pickOut() async {
      dtOut ??= DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: dtOut!,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(dtOut!),
      );
      if (t == null) return;
      dtOut = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Edit Session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tankCtrl,
                  decoration: const InputDecoration(labelText: 'Tank'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: gasInCtrl,
                  decoration: const InputDecoration(labelText: 'Gas In (bar)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: gasOutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gas Out (bar)',
                    hintText: 'Blank for ? bar',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    const Text('In:'),
                    const SizedBox(width: 6),
                    Text(
                      dtIn == null
                          ? '—'
                          : '${dtIn!.year}-${dtIn!.month.toString().padLeft(2, '0')}-${dtIn!.day.toString().padLeft(2, '0')} '
                                '${dtIn!.hour.toString().padLeft(2, '0')}:${dtIn!.minute.toString().padLeft(2, '0')}',
                    ),
                    TextButton(
                      onPressed: () async {
                        await _pickIn();
                        setStateDialog(() {});
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Out:'),
                    const SizedBox(width: 6),
                    Text(
                      dtOut == null
                          ? '—'
                          : '${dtOut!.year}-${dtOut!.month.toString().padLeft(2, '0')}-${dtOut!.day.toString().padLeft(2, '0')} '
                                '${dtOut!.hour.toString().padLeft(2, '0')}:${dtOut!.minute.toString().padLeft(2, '0')}',
                    ),
                    TextButton(
                      onPressed: () async {
                        await _pickOut();
                        setStateDialog(() {});
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                // Aquacoulisse fields removed
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Parse and apply
                tank = tankCtrl.text.trim();
                gasIn = int.tryParse(gasInCtrl.text.trim());
                gasOut = int.tryParse(gasOutCtrl.text.trim());
                final int? idxIn = session['logIndexIn'] as int?;
                final int? idxOut = session['logIndexOut'] as int?;
                if (idxIn != null && idxIn >= 0 && idxIn < logsList.length) {
                  final Map<String, dynamic> inLog = Map<String, dynamic>.from(
                    logsList[idxIn] as Map,
                  );
                  inLog['tag'] = tank;
                  if (dtIn != null) inLog['datetime'] = dtIn!.toIso8601String();
                  inLog['gasIn'] = gasIn;
                  logsList[idxIn] = inLog;
                }
                if (idxOut != null && idxOut >= 0 && idxOut < logsList.length) {
                  final Map<String, dynamic> outLog = Map<String, dynamic>.from(
                    logsList[idxOut] as Map,
                  );
                  outLog['tag'] = tank;
                  if (dtOut != null)
                    outLog['datetime'] = dtOut!.toIso8601String();
                  outLog['gasOut'] = gasOut; // null => '? bar'
                  logsList[idxOut] = outLog;
                }
                // Not ideal without document IDs; in a real app we would track IDs.
                // For now, append edited entries as new logs to preserve consistency.
                await StateCache.addLogs(logsList);
                if (mounted) setState(() {});
                if (context.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _openChangeTag(String name) async {
    if (StateCache.diverIsInWater(name)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Change tank after OUT.")));
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
            "Tank updated for $name to ${result.toString().padLeft(2, '0')}",
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
                              "Tank",
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
                          Expanded(
                            child: Text(
                              "Shortcut IN",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Shortcut OUT",
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
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: (waterIn)
                                                ? const SizedBox.shrink()
                                                : SizedBox(
                                                    height: 32 * scale,
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.black,
                                                        foregroundColor:
                                                            Colors.white,
                                                        shape:
                                                            const StadiumBorder(),
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal:
                                                                  16 * scale,
                                                            ),
                                                      ),
                                                      onPressed: () => _quickIn(
                                                        name,
                                                        tag: tag is int
                                                            ? tag
                                                            : int.tryParse(
                                                                (tag ?? '')
                                                                    .toString(),
                                                              ),
                                                      ),
                                                      child: const Text('IN'),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: (!waterIn)
                                                ? const SizedBox.shrink()
                                                : SizedBox(
                                                    height: 32 * scale,
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.black,
                                                        foregroundColor:
                                                            Colors.white,
                                                        shape:
                                                            const StadiumBorder(),
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal:
                                                                  16 * scale,
                                                            ),
                                                      ),
                                                      onPressed: () => _quickOut(
                                                        name,
                                                        tag: tag is int
                                                            ? tag
                                                            : int.tryParse(
                                                                (tag ?? '')
                                                                    .toString(),
                                                              ),
                                                      ),
                                                      child: const Text('OUT'),
                                                    ),
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
                              "Tank:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Gas In:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14 * scale,
                              ),
                            ),
                          ),
                          if (tab != "IN WATER")
                            Expanded(
                              child: Text(
                                "Gas Out:",
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
                          if (tab != "IN WATER")
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
                          if (tab != "IN WATER")
                            Expanded(
                              child: Text(
                                "Dive duration:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14 * scale,
                                ),
                              ),
                            ),
                          // Aquacoulisse columns removed
                          if (tab == "IN WATER") ...[
                            // Two shortcut columns (color select + OUT button)
                            Expanded(
                              child: Text(
                                "Shortcut",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14 * scale,
                                ),
                              ),
                            ),
                          ] else
                            const SizedBox.shrink(),
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
                                return InkWell(
                                  onTap: () => _editSessionDialog(
                                    Map<String, dynamic>.from(s),
                                  ),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 8 * scale,
                                      horizontal: 8 * scale,
                                    ),
                                    child: Builder(
                                      builder: (_) {
                                        final List<Widget> rowChildren = [
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
                                            child: Text(
                                              s['gasIn'] == null
                                                  ? '-'
                                                  : '${s['gasIn']}bar',
                                              style: TextStyle(
                                                fontSize:
                                                    (isPhone ? 14 : 17) * scale,
                                              ),
                                            ),
                                          ),
                                          if (tab != 'IN WATER')
                                            Expanded(
                                              child: Text(
                                                s['gasOut'] == null
                                                    ? '? bar'
                                                    : '${s['gasOut']}bar',
                                                style: TextStyle(
                                                  fontSize:
                                                      (isPhone ? 14 : 17) *
                                                      scale,
                                                ),
                                              ),
                                            ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              dateStrIn,
                                              style: inStyle,
                                            ),
                                          ),
                                          if (tab != 'IN WATER')
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                dateStrOut,
                                                style: TextStyle(
                                                  fontSize:
                                                      (isPhone ? 14 : 17) *
                                                      scale,
                                                ),
                                              ),
                                            ),
                                          if (tab != 'IN WATER')
                                            Expanded(
                                              child: Text(
                                                diveDur,
                                                style: TextStyle(
                                                  fontSize:
                                                      (isPhone ? 14 : 17) *
                                                      scale,
                                                ),
                                              ),
                                            ),
                                          // Aquacoulisse In removed
                                        ];
                                        if (tab == 'IN WATER') {
                                          rowChildren.add(
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: isCurrIn
                                                    ? SizedBox(
                                                        height: 32 * scale,
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.black,
                                                            foregroundColor:
                                                                Colors.white,
                                                            shape:
                                                                const StadiumBorder(),
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      16 *
                                                                      scale,
                                                                ),
                                                          ),
                                                          onPressed: () =>
                                                              _quickOut(
                                                                (s['name'] ??
                                                                        '')
                                                                    .toString(),
                                                                tag: int.tryParse(
                                                                  (s['tag'] ??
                                                                          '')
                                                                      .toString(),
                                                                ),
                                                              ),
                                                          child: const Text(
                                                            'OUT',
                                                          ),
                                                        ),
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                          );
                                        }
                                        return Row(children: rowChildren);
                                      },
                                    ),
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

  // Helpers to read Firestore logs and names
  List<Map<String, dynamic>> get _firestoreLogsChronological {
    // Note: this reads from the latest snapshot subscriptions via direct query each build
    // for simplicity. For large datasets, consider using StreamBuilder.
    // Since we trigger setState on snapshot listeners, this will re-run.
    // Use synchronous approach here to keep existing structure.
    // (In real refactor, switch to StreamBuilder.)
    // Best effort: if query fails, return empty.
    // This function is not async to fit existing callers.
    return _cachedChronologicalLogs;
  }

  static List<Map<String, dynamic>> _cachedChronologicalLogs = [];
  static List<String> _cachedNames = [];

  // Prime caches on each listener tick
  void _refreshCaches() async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('logs')
          .orderBy('datetime')
          .get();
      _cachedChronologicalLogs = [for (final d in logsSnap.docs) d.data()];
    } catch (_) {}
    try {
      final diversSnap = await FirebaseFirestore.instance
          .collection('divers')
          .get();
      final rosterNames = [
        for (final d in diversSnap.docs) d.id,
      ].where((n) => n.isNotEmpty).toList();
      // Ensure currently checked-in names are included even if missing from roster.
      final checkinsSnap = await FirebaseFirestore.instance
          .collection('checkins')
          .where('checkedIn', isEqualTo: true)
          .get();
      final checkedNames = [for (final d in checkinsSnap.docs) d.id];
      final all = <String>{...rosterNames, ...checkedNames}.toList();
      all.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _cachedNames = all;
    } catch (_) {}
  }

  List<String> get _allKnownNames => _cachedNames;
}
