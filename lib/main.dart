// main.dart (Web-ready + all recent features)
// -----------------------------------------------------------------------------
// Web changes:
// - Removed dart:io/path_provider/share_plus imports from main.dart.
// - HistoryPage CSV/XLS export now uses Exporter (conditional web/IO).
//
// Feature summary retained:
// - Deck Operator flow skips Department selection (Home → Aquacoulisse).
// - Operator IN/OUT works for ALL departments; selection persists across filters.
// - Tags required for ALL departments at Check-In.
// - Log highlights only the latest current-IN row per name|tag.
// - Change tag from Log → Checked‑In (any dept) when OUT.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

import 'utils/exporter/exporter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFFF8F6FA),
      statusBarColor: Color(0xFFF8F6FA),
    ),
  );

  await Hive.initFlutter();
  await Hive.openBox('divers'); // roster
  await Hive.openBox('logs'); // water IN/OUT events
  await Hive.openBox('prefs'); // settings
  await Hive.openBox('checkins'); // daily theater check-ins
  runApp(const MyApp());
}

const List<String> departments = [
  "SHOW DIVERS",
  "DAY CREW",
  "AUTOMATION",
  "H&F",
  "SFX",
  "LX",
  "SOUND",
  "WARDROBE",
  "STAGE MANAGEMENT",
  "HEALTH & SAFETY",
  "MANAGEMENT",
  "ARTISTIC",
  "VIP GUESTS",
  "OTHER",
];
const List<String> teams = ["BLUE", "GREEN", "RED", "WHITE"];

enum FlowMode { checkIn, operator }

// ===================== RESPONSIVE SCALING UTIL ======================
double appScale(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final shortest = size.shortestSide;
  double scale = shortest / 1000;
  return scale.clamp(0.6, 1.8);
}

double sf(BuildContext context, double base) => base * appScale(context);

// ===================== APP ROOT WITH THEME PERSISTENCE ======================
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Box prefs;
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    prefs = Hive.box('prefs');
    darkMode = prefs.get('darkMode', defaultValue: false);
  }

  void toggleDarkMode(bool value) {
    setState(() => darkMode = value);
    prefs.put('darkMode', darkMode);
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8F6FA),
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101316),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'THODW AQX',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===================== TOP ALERT ===============================
class TopAlert extends StatefulWidget {
  final int currentlyIn;
  final VoidCallback? onTap; // tap to open Log (ALL)
  const TopAlert({super.key, required this.currentlyIn, this.onTap});

  @override
  State<TopAlert> createState() => _TopAlertState();
}

class _TopAlertState extends State<TopAlert>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1, end: 0.25).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _text() {
    if (widget.currentlyIn == 0) return "All divers are OUT";
    if (widget.currentlyIn == 1) return "1 diver currently IN!";
    return "${widget.currentlyIn} Divers currently IN!";
  }

  Color _color() => widget.currentlyIn == 0 ? Colors.green : Colors.orange;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.currentlyIn == 0 ? "✅ " : "⚠️ ",
              style: TextStyle(fontSize: sf(context, 26)),
            ),
            Text(
              _text(),
              style: TextStyle(
                fontSize: sf(context, 22),
                fontWeight: FontWeight.bold,
                color: _color(),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      top: sf(context, 12),
      left: 0,
      right: 0,
      child: widget.onTap == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onTap,
              child: content,
            ),
    );
  }
}

// ===================== UTIL ============================
Future<int> getCurrentlyInCount() async {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  final List<Map> logsList = List<Map>.from(logs);
  final Map<String, Map> lastLogByDiverTag = {};
  for (final log in logsList.reversed) {
    final key = "${log['name'] ?? ''}|${log['tag'] ?? ''}";
    if (!lastLogByDiverTag.containsKey(key)) {
      lastLogByDiverTag[key] = log;
    }
  }
  return lastLogByDiverTag.values
      .where((l) => (l['status'] ?? '') == 'IN')
      .length;
}

bool diverIsInWater(String name) {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  final list = List<Map>.from(logs);
  final diverLogs = list.where((l) => l['name'] == name).toList();
  if (diverLogs.isEmpty) return false;
  return diverLogs.last['status'] == 'IN';
}

int? lastInTag(String name) {
  final logsBox = Hive.box('logs');
  final logs = logsBox.get('logsList', defaultValue: <Map>[]);
  for (final log in List<Map>.from(logs).reversed) {
    if (log['name'] == name && log['status'] == 'IN') return log['tag'];
  }
  return null;
}

bool isCheckedIn(String name) {
  final box = Hive.box('checkins');
  final data = (box.get(name) ?? {}) as Map;
  return (data['checkedIn'] ?? false) == true;
}

int? checkedInTag(String name) {
  final box = Hive.box('checkins');
  final data = (box.get(name) ?? {}) as Map;
  if (data.isEmpty) return null;
  return data['tag'] is int ? data['tag'] : int.tryParse("${data['tag']}");
}

bool tagInUse(int tag, {String? exceptName}) {
  final box = Hive.box('checkins');
  for (final key in box.keys) {
    if (key == exceptName) continue;
    final data = (box.get(key) ?? {}) as Map;
    if ((data['checkedIn'] ?? false) == true) {
      final t = data['tag'];
      final val = t is int ? t : int.tryParse("$t");
      if (val == tag) return true;
    }
  }
  return false;
}

Color teamColor(String team) {
  switch (team.toUpperCase()) {
    case 'BLUE':
      return Colors.blue;
    case 'GREEN':
      return Colors.green;
    case 'RED':
      return Colors.red;
    case 'WHITE':
      return Colors.grey;
    default:
      return Colors.black;
  }
}

Color aquacoulisseColor(String c) => teamColor(c);

// Helper: navigate home
void goHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
    (route) => false,
  );
}

// ===================== HOME SCREEN =========================================
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
      // Skip department screen for Deck Operator
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
          TopAlert(
            currentlyIn: currentlyIn,
            onTap: _openLog, // tap alert to open Log ALL
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

// ===================== DEPARTMENT SCREEN (Check-In only) ====================
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
    final scale = appScale(context);
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
                SizedBox(width: 4 * scale),
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

// ===================== AQUACOULISSE SCREEN =================
class AquacoulisseScreen extends StatefulWidget {
  final String?
  department; // optional; null when coming from Home (Deck Operator)
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

// ===================== CHECK-IN NAMES/TAGS SCREEN (ALL depts; tags required)
class CheckInNamesScreen extends StatefulWidget {
  final String department;
  const CheckInNamesScreen({super.key, required this.department});

  @override
  State<CheckInNamesScreen> createState() => _CheckInNamesScreenState();
}

class _CheckInNamesScreenState extends State<CheckInNamesScreen> {
  late Box diversBox;
  late Box checkinsBox;
  List<Map> divers = [];
  String selectedTeam = teams.first;
  String? selectedDiver;
  int? selectedTag;
  int tagPage = 0;

  int currentlyIn = 0;
  Timer? _timer;

  static const int tagsPerPage = 20;

  bool get isShowDivers => widget.department == "SHOW DIVERS";

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    divers = list.where((d) => d['department'] == widget.department).toList();
    setState(() {});
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

  List<Map> get displayedDivers {
    if (isShowDivers) {
      return divers.where((d) => d['team'] == selectedTeam).toList();
    }
    return divers; // all names for non-Show-Divers
  }

  List<int> get currentTagPage {
    final start = tagPage * tagsPerPage + 1;
    return List.generate(
      tagsPerPage,
      (i) => start + i,
    ).where((n) => n <= 100).toList();
  }

  int get maxTagPage => (100 / tagsPerPage).ceil();

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _cancel() {
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      tagPage = 0;
    });
  }

  void _confirm() {
    if (selectedDiver == null || selectedTag == null) {
      _snack("Please select a tag number.");
      return;
    }
    if (isCheckedIn(selectedDiver!)) {
      _snack("Already checked in. Change tag from Log → Checked‑In.");
      return;
    }
    if (tagInUse(selectedTag!)) {
      _snack(
        "Tag ${selectedTag!.toString().padLeft(2, '0')} is already in use.",
      );
      return;
    }
    // All departments store tag at check-in
    checkinsBox.put(selectedDiver!, {
      'checkedIn': true,
      'tag': selectedTag!,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _snack("Checked in!");
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      tagPage = 0;
    });
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
    final scale = appScale(context);
    final isPhone = MediaQuery.of(context).size.width < 600;

    final crossAxisCount = isPhone ? 2 : 4;
    final childAspect = isPhone ? 1.8 : 2.45;
    final gridSpacing = 12.0 * scale;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn, onTap: _openLog),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(isPhone ? 6 : 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, size: 28 * scale),
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        tooltip: "Home",
                        icon: Icon(Icons.home_outlined, size: 26 * scale),
                        onPressed: () => goHome(context),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 22 * scale,
                            vertical: 10 * scale,
                          ),
                          textStyle: TextStyle(
                            fontSize: 18 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _openLog,
                        child: const Text('  Log  '),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    "${widget.department} - CHECK IN",
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),

                  // Team filter only for SHOW DIVERS
                  if (isShowDivers)
                    Wrap(
                      spacing: 6 * scale,
                      runSpacing: 6 * scale,
                      children: [
                        for (final t in teams)
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                selectedTeam = t;
                                selectedDiver = null;
                                selectedTag = null;
                                tagPage = 0;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedTeam == t
                                  ? teamColor(t)
                                  : Colors.grey[100],
                              foregroundColor: selectedTeam == t
                                  ? (t == "WHITE" ? Colors.black : Colors.white)
                                  : Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18 * scale),
                              ),
                              elevation: 0,
                              minimumSize: Size(120 * scale, 48 * scale),
                              textStyle: TextStyle(
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: Text("$t TEAM"),
                          ),
                      ],
                    ),

                  if (isShowDivers) SizedBox(height: 8 * scale),

                  Expanded(
                    child: Row(
                      children: [
                        // Left: names or tag grid
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              if (selectedDiver == null)
                                Expanded(
                                  child: displayedDivers.isEmpty
                                      ? Center(
                                          child: Text(
                                            "No names found.\nAdd in Settings.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 18 : 22) * scale,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        )
                                      : GridView.count(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: gridSpacing,
                                          crossAxisSpacing: gridSpacing,
                                          childAspectRatio: childAspect,
                                          children: [
                                            for (final person
                                                in displayedDivers)
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  minimumSize: Size(
                                                    120 * scale,
                                                    60 * scale,
                                                  ),
                                                  backgroundColor: isShowDivers
                                                      ? teamColor(selectedTeam)
                                                      : Colors.blueGrey,
                                                  foregroundColor:
                                                      (isShowDivers &&
                                                          selectedTeam ==
                                                              "WHITE")
                                                      ? Colors.black
                                                      : Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          22 * scale,
                                                        ),
                                                  ),
                                                  textStyle: TextStyle(
                                                    fontSize:
                                                        (isPhone ? 14 : 16) *
                                                        scale,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  elevation: 0,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    selectedDiver =
                                                        person['name'];
                                                    selectedTag = null;
                                                    tagPage = 0;
                                                  });
                                                },
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    person['name'] ?? '',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              if (selectedDiver != null) ...[
                                // Tag page buttons (for all departments)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 8 * scale),
                                  child: Row(
                                    children: [
                                      ElevatedButton(
                                        onPressed: _cancel,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red[400],
                                          foregroundColor: Colors.white,
                                          minimumSize: Size(
                                            120 * scale,
                                            54 * scale,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              24 * scale,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: 16 * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        child: const Text("Cancel"),
                                      ),
                                      SizedBox(width: 16 * scale),
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
                                              for (
                                                int i = 0;
                                                i < maxTagPage;
                                                i++
                                              )
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
                                                      backgroundColor:
                                                          tagPage == i
                                                          ? Colors.blue
                                                          : Colors.grey[100],
                                                      foregroundColor:
                                                          tagPage == i
                                                          ? Colors.white
                                                          : Colors.black,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              18 * scale,
                                                            ),
                                                      ),
                                                      elevation: 0,
                                                      minimumSize: Size(
                                                        90 * scale,
                                                        48 * scale,
                                                      ),
                                                      textStyle: TextStyle(
                                                        fontSize: 14 * scale,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      "${(i * tagsPerPage + 1).toString().padLeft(2, '0')}-${((i + 1) * tagsPerPage).clamp(1, 100).toString().padLeft(2, '0')}",
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Tag grid (for all departments)
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
                                            final inUse = tagInUse(t);
                                            final bool isSelected =
                                                selectedTag == t;
                                            final Color bg = isSelected
                                                ? (isShowDivers
                                                      ? teamColor(selectedTeam)
                                                      : Colors.black)
                                                : (inUse
                                                      ? Colors.grey[400]!
                                                      : Colors.grey[300]!);
                                            final Color fg = isSelected
                                                ? (isShowDivers &&
                                                          selectedTeam ==
                                                              "WHITE"
                                                      ? Colors.black
                                                      : Colors.white)
                                                : Colors.black;
                                            return ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: bg,
                                                foregroundColor: fg,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        22 * scale,
                                                      ),
                                                ),
                                                elevation: 0,
                                              ),
                                              onPressed: inUse
                                                  ? () => _snack(
                                                      "Tag ${t.toString().padLeft(2, '0')} is already in use.",
                                                    )
                                                  : () => setState(
                                                      () => selectedTag = t,
                                                    ),
                                              child: Text(
                                                t.toString().padLeft(2, '0'),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Right panel: selected diver and Confirm
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 12 * scale : 28 * scale,
                              horizontal: 8 * scale,
                            ),
                            child: Column(
                              children: [
                                if (selectedDiver != null)
                                  Text(
                                    selectedDiver!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: (isPhone ? 30 : 42) * scale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (selectedTag != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 10 * scale),
                                    child: Text(
                                      selectedTag!.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: (isPhone ? 26 : 36) * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                SizedBox(
                                  width: (isPhone ? 160 : 200) * scale,
                                  height: (isPhone ? 60 : 70) * scale,
                                  child: ElevatedButton(
                                    onPressed:
                                        (selectedDiver != null &&
                                            selectedTag != null)
                                        ? _confirm
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          36 * scale,
                                        ),
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
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== OPERATOR SCREEN (IN/OUT for ALL departments) ========
class OperatorScreen extends StatefulWidget {
  final String department;
  final String aquacoulisse;
  const OperatorScreen({
    super.key,
    required this.department,
    required this.aquacoulisse,
  });

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  late Box diversBox;
  late Box logsBox;
  late Box checkinsBox;
  List<Map> divers = []; // SHOW DIVERS roster
  String selectedTeam = teams.first;

  // When a non-Show-Divers department is selected, this is set.
  String? selectedDepartmentFilter;

  final Set<String> selectedDivers = {}; // diver names (any department)
  int currentlyIn = 0;
  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    logsBox = Hive.box('logs');
    checkinsBox = Hive.box('checkins');
    _loadDivers();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    divers = list.where((d) => d['department'] == "SHOW DIVERS").toList();
    setState(() {});
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

  // ================== Filters and data ==================
  List<Map> get checkedInDiversForTeam {
    final teamDivers = divers.where((d) => d['team'] == selectedTeam);
    return teamDivers.where((d) => isCheckedIn(d['name'])).toList();
  }

  String? _departmentForName(String name) {
    final list = List<Map>.from(
      diversBox.get('diversList', defaultValue: <Map>[]),
    );
    for (final d in list) {
      if ((d['name'] ?? '') == name) return d['department'];
    }
    return null;
  }

  List<String> get nonShowDepartmentsWithCheckins {
    final box = checkinsBox;
    final Set<String> depts = {};
    for (final key in box.keys) {
      final data = (box.get(key) ?? {}) as Map;
      if ((data['checkedIn'] ?? false) == true) {
        final dept = _departmentForName(key as String);
        if (dept != null && dept != "SHOW DIVERS") {
          depts.add(dept);
        }
      }
    }
    // Keep UI order consistent with global departments list
    final ordered = [
      for (final dep in departments)
        if (depts.contains(dep) && dep != "SHOW DIVERS") dep,
    ];
    return ordered;
  }

  List<String> get checkedInNamesForSelectedDepartment {
    if (selectedDepartmentFilter == null) return [];
    final list = List<Map>.from(
      diversBox.get('diversList', defaultValue: <Map>[]),
    );
    final deptNames = list
        .where((d) => d['department'] == selectedDepartmentFilter)
        .map((d) => (d['name'] ?? '').toString())
        .where((n) => n.isNotEmpty && isCheckedIn(n))
        .toList();
    deptNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return deptNames;
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _playConfirm() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/pling.mp3'));
    } catch (_) {}
  }

  void _toggleSelect(String name) {
    setState(() {
      if (selectedDivers.contains(name)) {
        selectedDivers.remove(name);
      } else {
        selectedDivers.add(name);
      }
    });
  }

  bool get allSelectedAreOut =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((n) => !diverIsInWater(n));

  bool get allSelectedAreIn =>
      selectedDivers.isNotEmpty &&
      selectedDivers.every((n) => diverIsInWater(n));

  bool get mixedSelection =>
      selectedDivers.isNotEmpty && !(allSelectedAreOut || allSelectedAreIn);

  Future<void> _batchIn() async {
    if (!allSelectedAreOut) return;
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    for (final name in selectedDivers) {
      final tag = checkedInTag(name);
      if (tag == null) {
        _snack("No tag for $name. Assign a tag from Log → Checked‑In.");
        continue;
      }
      logs.add({
        'name': name,
        'status': 'IN',
        'tag': tag,
        'datetime': DateTime.now().toIso8601String(),
        'aquacoulisse': widget.aquacoulisse,
      });
    }
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Checked IN ${selectedDivers.length} diver(s).");
    setState(() {
      selectedDivers.clear();
    });
  }

  Future<void> _batchOut() async {
    if (!allSelectedAreIn) return;
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    for (final name in selectedDivers) {
      final lt = lastInTag(name);
      logs.add({
        'name': name,
        'status': 'OUT',
        'tag': lt ?? '',
        'datetime': DateTime.now().toIso8601String(),
        'aquacoulisse': widget.aquacoulisse,
      });
    }
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Checked OUT ${selectedDivers.length} diver(s).");
    setState(() {
      selectedDivers.clear();
    });
  }

  void _openLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(selectedColor: widget.aquacoulisse),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final scale = appScale(context);

    // grid for names view
    final crossAxisCount = isPhone ? 2 : 4;
    final childAspect = isPhone ? 1.8 : 2.45;
    final gridSpacing = 12.0 * scale;

    final inOutButtonSize = Size(
      (isPhone ? 140 : 180) * scale,
      (isPhone ? 56 : 68) * scale,
    );
    final inOutTextSize = (isPhone ? 20 : 22) * scale;

    final showDiversMode = selectedDepartmentFilter == null;

    // Data for left grid depending on filter
    final List<Widget> leftTiles = [];
    if (showDiversMode) {
      final list = checkedInDiversForTeam;
      if (list.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No checked-in divers for $selectedTeam.",
              style: TextStyle(
                fontSize: (isPhone ? 18 : 22) * scale,
                color: Colors.grey[600],
              ),
            ),
          ),
        );
      } else {
        leftTiles.add(
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gridSpacing,
            crossAxisSpacing: gridSpacing,
            childAspectRatio: childAspect,
            children: [
              for (final d in list)
                Builder(
                  builder: (_) {
                    final name = d['name'] as String;
                    final waterIn = diverIsInWater(name);
                    final bool isSel = selectedDivers.contains(name);
                    final Color bg = isSel
                        ? Colors.green
                        : aquacoulisseColor(widget.aquacoulisse);
                    final int? tag = checkedInTag(name);
                    return Stack(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(120 * scale, 60 * scale),
                            backgroundColor: bg,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            textStyle: TextStyle(
                              fontSize: (isPhone ? 14 : 16) * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _toggleSelect(name),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tag == null
                                  ? name
                                  : "$name  (Tag ${tag.toString().padLeft(2, '0')})",
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: waterIn
                                  ? Colors.orange[600]
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              waterIn ? "IN" : "OUT",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      }
    } else {
      final names = checkedInNamesForSelectedDepartment;
      if (names.isEmpty) {
        leftTiles.add(
          Center(
            child: Text(
              "No one checked in from $selectedDepartmentFilter.",
              style: TextStyle(
                fontSize: (isPhone ? 18 : 22) * scale,
                color: Colors.grey[600],
              ),
            ),
          ),
        );
      } else {
        leftTiles.add(
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gridSpacing,
            crossAxisSpacing: gridSpacing,
            childAspectRatio: childAspect,
            children: [
              for (final name in names)
                Builder(
                  builder: (_) {
                    final waterIn = diverIsInWater(name);
                    final bool isSel = selectedDivers.contains(name);
                    final int? tag = checkedInTag(name);
                    final Color bg = isSel
                        ? Colors.green
                        : Colors.blueGrey; // neutral for other depts
                    return Stack(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(120 * scale, 60 * scale),
                            backgroundColor: bg,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            textStyle: TextStyle(
                              fontSize: (isPhone ? 14 : 16) * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _toggleSelect(name),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tag == null
                                  ? name
                                  : "$name  (Tag ${tag.toString().padLeft(2, '0')})",
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: waterIn
                                  ? Colors.orange[600]
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              waterIn ? "IN" : "OUT",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn, onTap: _openLog),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(isPhone ? 6 : 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, size: 28 * scale),
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        tooltip: "Home",
                        icon: Icon(Icons.home_outlined, size: 26 * scale),
                        onPressed: () => goHome(context),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 22 * scale,
                            vertical: 10 * scale,
                          ),
                          textStyle: TextStyle(
                            fontSize: 18 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _openLog,
                        child: const Text('  Log  '),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    "${widget.department} - ${widget.aquacoulisse} AQUACOULISSE",
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: aquacoulisseColor(widget.aquacoulisse),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),

                  // Filters: Teams + dynamic departments with check-ins
                  Wrap(
                    spacing: 6 * scale,
                    runSpacing: 6 * scale,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in teams)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              selectedDepartmentFilter = null;
                              selectedTeam = t;
                              // keep selection across filters
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (selectedDepartmentFilter == null &&
                                    selectedTeam == t)
                                ? teamColor(t)
                                : Colors.grey[100],
                            foregroundColor:
                                (selectedDepartmentFilter == null &&
                                    selectedTeam == t)
                                ? (t == "WHITE" ? Colors.black : Colors.white)
                                : Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18 * scale),
                            ),
                            elevation: 0,
                            minimumSize: Size(120 * scale, 48 * scale),
                            textStyle: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: Text("$t TEAM"),
                        ),
                      if (nonShowDepartmentsWithCheckins.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                          child: Text(
                            "•",
                            style: TextStyle(
                              fontSize: 20 * scale,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      for (final dep in nonShowDepartmentsWithCheckins)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              selectedDepartmentFilter = dep;
                              // keep selection across filters
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedDepartmentFilter == dep
                                ? Colors.blueGrey[700]
                                : Colors.grey[100],
                            foregroundColor: selectedDepartmentFilter == dep
                                ? Colors.white
                                : Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18 * scale),
                            ),
                            elevation: 0,
                            minimumSize: Size(120 * scale, 48 * scale),
                            textStyle: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: Text(dep),
                        ),
                    ],
                  ),

                  SizedBox(height: 8 * scale),

                  Expanded(
                    child: Row(
                      children: [
                        // Left: grid area
                        Expanded(
                          flex: 2,
                          child: leftTiles.isEmpty
                              ? const SizedBox.shrink()
                              : leftTiles.first,
                        ),
                        // Right: selection basket + IN/OUT (for all departments)
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 12 * scale : 28 * scale,
                              horizontal: 8 * scale,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  "Selected (${selectedDivers.length})",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: (isPhone ? 20 : 22) * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8 * scale),
                                Expanded(
                                  child: selectedDivers.isEmpty
                                      ? Center(
                                          child: Text(
                                            "Tap names to select.\nYou can switch teams/departments; selection stays.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        )
                                      : ListView(
                                          children: [
                                            for (final name
                                                in selectedDivers.toList())
                                              ListTile(
                                                dense: true,
                                                title: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  "Tag ${checkedInTag(name)?.toString().padLeft(2, '0') ?? '--'} • ${diverIsInWater(name) ? 'IN' : 'OUT'}",
                                                ),
                                                trailing: IconButton(
                                                  icon: const Icon(Icons.close),
                                                  onPressed: () =>
                                                      _toggleSelect(name),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                                if (mixedSelection)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8 * scale),
                                    child: Text(
                                      "Selection includes both IN and OUT divers.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: inOutButtonSize.width,
                                      height: inOutButtonSize.height,
                                      child: ElevatedButton(
                                        onPressed: allSelectedAreOut
                                            ? _batchIn
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              36 * scale,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: inOutTextSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        child: const Text("IN"),
                                      ),
                                    ),
                                    SizedBox(width: 26 * scale),
                                    SizedBox(
                                      width: inOutButtonSize.width,
                                      height: inOutButtonSize.height,
                                      child: ElevatedButton(
                                        onPressed: allSelectedAreIn
                                            ? _batchOut
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              36 * scale,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: inOutTextSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        child: const Text("OUT"),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== SETTINGS PAGE =======================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Box diversBox;
  int currentlyIn = 0;
  Timer? _timer;
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    darkMode = Hive.box('prefs').get('darkMode', defaultValue: false);
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

  List<Map> get divers {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    list.sort(
      (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
        (b['name'] ?? '').toLowerCase(),
      ),
    );
    return list;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _showAddDialog() {
    String newName = '';
    String selectedDepartment = departments.first;
    String? selectedTeam = teams.first;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Add Diver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Diver Name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => newName = v,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final dep in departments)
                    DropdownMenuItem(value: dep, child: Text(dep)),
                ],
                onChanged: (val) {
                  setStateDialog(() {
                    selectedDepartment = val!;
                    if (selectedDepartment == "SHOW DIVERS") {
                      selectedTeam ??= teams.first;
                    } else {
                      selectedTeam = null;
                    }
                  });
                },
              ),
              if (selectedDepartment == "SHOW DIVERS") ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedTeam,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in teams)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (val) => setStateDialog(() => selectedTeam = val),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                if (newName.trim().isEmpty) {
                  _snack("Diver name can't be empty.");
                  return;
                }
                final arr = diversBox.get('diversList', defaultValue: <Map>[]);
                if (List<Map>.from(arr).any(
                  (d) =>
                      (d['name'] ?? '').toLowerCase() ==
                      newName.trim().toLowerCase(),
                )) {
                  _snack("Diver already exists.");
                  return;
                }
                final list = List<Map>.from(arr);
                list.add({
                  'name': newName.trim(),
                  'department': selectedDepartment,
                  'team': selectedTeam,
                });
                diversBox.put('diversList', list);
                Navigator.pop(ctx);
                setState(() {});
                _snack("Diver added!");
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove Diver"),
        content: Text("Are you sure you want to remove '$name'?"),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text('Remove'),
            onPressed: () {
              final arr = diversBox.get('diversList', defaultValue: <Map>[]);
              final list = List<Map>.from(arr);
              list.removeWhere((d) => d['name'] == name);
              diversBox.put('diversList', list);
              Navigator.pop(context);
              setState(() {});
              _snack("Diver removed.");
            },
          ),
        ],
      ),
    );
  }

  void _toggleDark(bool value) {
    MyApp.of(context)?.toggleDarkMode(value);
    setState(() => darkMode = value);
  }

  void _resetCheckIns() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Day Reset"),
        content: const Text(
          "This will clear today's CHECKED‑IN list.\n"
          "Water IN/OUT logs will NOT be affected.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reset"),
            onPressed: () async {
              await Hive.box('checkins').clear();
              if (context.mounted) {
                Navigator.pop(context);
                _snack("Checked‑In list cleared.");
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final list = divers;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(
            currentlyIn: currentlyIn,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HistoryPage(selectedColor: "ALL"),
                ),
              );
            },
          ),
          SafeArea(
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
                      "Settings",
                      style: TextStyle(
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                SizedBox(height: 10 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.add, size: 24 * scale),
                    label: Text(
                      'Add Diver',
                      style: TextStyle(fontSize: 20 * scale),
                    ),
                    onPressed: _showAddDialog,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(50 * scale),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16 * scale),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.refresh, size: 24 * scale),
                    label: Text(
                      'New Day Reset (Checked‑In only)',
                      style: TextStyle(fontSize: 18 * scale),
                    ),
                    onPressed: _resetCheckIns,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(48 * scale),
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: 12 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Dark theme",
                      style: TextStyle(
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: darkMode,
                    onChanged: _toggleDark,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              "No divers yet.\nTap 'Add Diver' to get started.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20 * scale,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = list[i];
                              String subtitle = d['department'] ?? '';
                              if (d['department'] == "SHOW DIVERS" &&
                                  d['team'] != null) {
                                subtitle += " - ${d['team']}";
                              }
                              return ListTile(
                                title: Text(
                                  d['name'] ?? '',
                                  style: TextStyle(fontSize: 20 * scale),
                                ),
                                subtitle: Text(
                                  subtitle,
                                  style: TextStyle(fontSize: 14 * scale),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 22 * scale,
                                  ),
                                  onPressed: () => _confirmRemove(d['name']),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== HISTORY / LOG PAGE ===================
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

  // Logs with IN-first ordering, using per-row _isCurrentlyIn flag (only latest row)
  List<Map> getLogsFiltered() {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    // newest first
    List<Map> logsList = List<Map>.from(logs).reversed.toList();

    // filter by aquacoulisse for non-Checked-In tabs
    if (tab != "ALL" && tab != "CHECKED-IN") {
      logsList = logsList
          .where(
            (log) =>
                (log['aquacoulisse'] ?? '').toString().toUpperCase() == tab,
          )
          .toList();
    }

    // Compute durations for OUT rows
    final Map<String, Map> lastIN = {};
    for (int i = logsList.length - 1; i >= 0; i--) {
      final log = logsList[i];
      if (log['status'] == 'IN') {
        lastIN["${log['name']}|${log['tag']}"] = log;
      } else if (log['status'] == 'OUT') {
        final key = "${log['name']}|${log['tag']}";
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

    // Find latest index for each (name|tag)
    final Map<String, int> latestIndexByKey = {};
    for (int i = 0; i < logsList.length; i++) {
      final k = "${logsList[i]['name']}|${logsList[i]['tag']}";
      latestIndexByKey.putIfAbsent(k, () => i); // newest-first list
    }

    // Flag only the latest row as currently IN when its status is IN
    final Set<int> isLatestInIndex = {};
    latestIndexByKey.forEach((k, idx) {
      if ((logsList[idx]['status'] ?? '') == 'IN') {
        isLatestInIndex.add(idx);
      }
    });

    for (int i = 0; i < logsList.length; i++) {
      logsList[i]['_isCurrentlyIn'] = isLatestInIndex.contains(i);
    }

    // Sort by per-row flag first, then by datetime desc
    logsList.sort((a, b) {
      final ai = (a['_isCurrentlyIn'] ?? false) == true ? 1 : 0;
      final bi = (b['_isCurrentlyIn'] ?? false) == true ? 1 : 0;
      if (ai != bi) return bi - ai; // true first
      final ad = DateTime.tryParse(a['datetime'] ?? '') ?? DateTime(1970);
      final bd = DateTime.tryParse(b['datetime'] ?? '') ?? DateTime(1970);
      return bd.compareTo(ad);
    });

    return logsList;
  }

  List<Map<String, dynamic>> getCheckedInList() {
    final box = checkinsBox;
    final List<Map<String, dynamic>> arr = [];
    for (final key in box.keys) {
      final data = (box.get(key) ?? {}) as Map;
      if ((data['checkedIn'] ?? false) == true) {
        arr.add({
          'name': key as String,
          'tag': data['tag'],
          'timestamp': data['timestamp'],
          'waterIn': diverIsInWater(key as String),
          'department': _departmentFor(key as String),
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

  // Build CSV/XLS strings, then delegate saving to Exporter (web/IO aware)
  String _buildCsv() {
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
    return buffer.toString();
  }

  String _buildXlsXml() {
    final logs = getLogsFiltered();
    final sb = StringBuffer();
    sb.writeln(r'<?xml version="1.0"?>');
    sb.writeln(
      '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
      'xmlns:o="urn:schemas-microsoft-com:office:office" '
      'xmlns:x="urn:schemas-microsoft-com:office:excel" '
      'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
    );
    sb.writeln('<Worksheet ss:Name="DiveHistory"><Table>');

    List<String> headers = [
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

    sb.writeln('</Table></Worksheet></Workbook>');
    return sb.toString();
  }

  Future<void> _exportCSV() async {
    await Exporter.saveCsv(_timestampBase(), _buildCsv());
  }

  Future<void> _exportXlsXml() async {
    await Exporter.saveXls(_timestampBase(), _buildXlsXml());
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
    // Allow tag changes for ANY department, but only when OUT
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
          // In Log page, tapping alert switches to ALL tab
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
                    // Checked-in list view
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
                    // Logs view (orange IN only on the latest current-IN row)
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

// ===================== CHANGE TAG SCREEN (from Log → Checked‑In) ===========
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

    // Match the Check-In grid sizes exactly
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
