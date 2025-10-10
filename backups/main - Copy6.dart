// main.dart (FULL UPDATED FILE)
// -----------------------------------------------------------------------------
// Change in this version:
// - On the third screen (Names/Tags), the SHOW DIVERS team buttons now highlight
//   in their own team color (BLUE/GREEN/RED/WHITE) instead of the aquacoulisse color.
// - Previous behavior retained:
//   * Team buttons are only visible while selecting a diver (hidden in tag mode).
//   * When a selected diver is currently IN, tag selection UI is hidden.
//   * AQUACOULISSE spelling in titles.
//   * 4x5 grid for tags on larger screens, 2 columns on phones.
//   * Enlarged IN/OUT buttons, History buttons on screens, exports, alerts, etc.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  await Hive.openBox('divers');
  await Hive.openBox('logs');
  await Hive.openBox('prefs');
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
      home: const DepartmentScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===================== TOP ALERT ===============================
class TopAlert extends StatefulWidget {
  final int currentlyIn;
  const TopAlert({super.key, required this.currentlyIn});

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
    return Positioned(
      top: sf(context, 12),
      left: 0,
      right: 0,
      child: AnimatedBuilder(
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

// ===================== DEPARTMENT SCREEN ===================================
class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen({super.key});
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

  void _openAquacoulisse(String department) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AquacoulisseScreen(department: department),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistoryPage(selectedColor: "ALL"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn),
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
              onPressed: _openHistory,
              child: const Text("History"),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: sf(context, 70)),
                  Text(
                    'Choose your department:',
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
                          onPressed: () => _openAquacoulisse(dep),
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

// ===================== AQUACOULISSE SCREEN (CENTERED) ======================
class AquacoulisseScreen extends StatefulWidget {
  final String department;
  const AquacoulisseScreen({super.key, required this.department});

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

  void _goToNames(String color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NamesTagsScreen(department: widget.department, aquacoulisse: color),
      ),
    );
  }

  void _openHistory() {
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
          TopAlert(currentlyIn: currentlyIn),
          Positioned(
            top: topPad + sf(context, 6),
            left: sf(context, 8),
            child: IconButton(
              icon: Icon(Icons.arrow_back, size: sf(context, 28)),
              onPressed: () => Navigator.pop(context),
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
              onPressed: _openHistory,
              child: const Text("History"),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.department,
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
                        onPressed: () => _goToNames(c),
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

// ===================== NAMES / TAGS / IN-OUT SCREEN ========================
class NamesTagsScreen extends StatefulWidget {
  final String department;
  final String aquacoulisse;
  const NamesTagsScreen({
    super.key,
    required this.department,
    required this.aquacoulisse,
  });

  @override
  State<NamesTagsScreen> createState() => _NamesTagsScreenState();
}

class _NamesTagsScreenState extends State<NamesTagsScreen> {
  late Box diversBox;
  late Box logsBox;
  List<Map> divers = [];
  String? selectedTeam;
  String? selectedDiver;
  int? selectedTag;
  int tagPage = 0;
  int currentlyIn = 0;
  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const int tagsPerPage = 20;

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    logsBox = Hive.box('logs');
    _loadDivers();
    _updateCount();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCount());
    if (widget.department == "SHOW DIVERS") selectedTeam = teams.first;
  }

  Future<void> _updateCount() async {
    final c = await getCurrentlyInCount();
    if (mounted) setState(() => currentlyIn = c);
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    divers = list.where((d) {
      if (widget.department == "SHOW DIVERS") {
        return d['department'] == "SHOW DIVERS";
      }
      return d['department'] == widget.department;
    }).toList();
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Map> get diversForCurrentTeam {
    if (widget.department == "SHOW DIVERS") {
      return divers.where((d) => d['team'] == selectedTeam).toList();
    }
    return divers;
  }

  List<int> get currentTagPage {
    final start = tagPage * tagsPerPage + 1;
    return List.generate(
      tagsPerPage,
      (i) => start + i,
    ).where((n) => n <= 100).toList();
  }

  int get maxTagPage => (100 / tagsPerPage).ceil();

  Future<void> _playConfirm() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/pling.mp3'));
    } catch (_) {}
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  Color getAquacoulisseColor() {
    switch (widget.aquacoulisse.toUpperCase()) {
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

  // NEW: color for each team button by its own name color
  Color colorForTeam(String team) {
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

  bool _diverIsIn(String name) {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    final list = List<Map>.from(logs);
    final diverLogs = list.where((l) => l['name'] == name).toList();
    if (diverLogs.isEmpty) return false;
    return diverLogs.last['status'] == 'IN';
  }

  int? _lastInTag(String name) {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    for (final log in List<Map>.from(logs).reversed) {
      if (log['name'] == name && log['status'] == 'IN') return log['tag'];
    }
    return null;
  }

  Future<void> _logIn() async {
    if (selectedDiver == null) return;
    if (selectedTag == null) {
      _snack("Please select a tag number.");
      return;
    }
    if (_diverIsIn(selectedDiver!)) {
      _snack("Diver already IN.");
      return;
    }
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    logs.add({
      'name': selectedDiver!,
      'status': 'IN',
      'tag': selectedTag!,
      'datetime': DateTime.now().toIso8601String(),
      'aquacoulisse': widget.aquacoulisse,
    });
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Diver checked IN.");
    setState(() {
      selectedDiver = null;
      selectedTag = null;
    });
  }

  Future<void> _logOut() async {
    if (selectedDiver == null) return;
    if (!_diverIsIn(selectedDiver!)) {
      _snack("Diver already OUT.");
      return;
    }
    final lt = _lastInTag(selectedDiver!);
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    logs.add({
      'name': selectedDiver!,
      'status': 'OUT',
      'tag': lt ?? '',
      'datetime': DateTime.now().toIso8601String(),
      'aquacoulisse': widget.aquacoulisse,
    });
    await logsBox.put('logsList', logs);
    await _playConfirm();
    _snack("Diver checked OUT.");
    setState(() {
      selectedDiver = null;
      selectedTag = null;
    });
  }

  void _cancel() {
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      tagPage = 0;
    });
  }

  String teamDisplay(String t) => "$t TEAM";

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final scale = appScale(context);

    final crossAxisCount = isPhone ? 2 : 4;
    final childAspect = isPhone ? 1.8 : 2.45;
    final gridSpacing = 12.0 * scale;

    final colorBtnStyle = ElevatedButton.styleFrom(
      minimumSize: Size(120 * scale, 60 * scale),
      backgroundColor: getAquacoulisseColor(),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22 * scale),
      ),
      textStyle: TextStyle(
        fontSize: (isPhone ? 14 : 16) * scale,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 8 * scale),
    );
    final neutralBtnStyle = ElevatedButton.styleFrom(
      minimumSize: Size(120 * scale, 60 * scale),
      backgroundColor: Colors.grey[300],
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22 * scale),
      ),
      textStyle: TextStyle(
        fontSize: (isPhone ? 14 : 16) * scale,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 8 * scale),
    );

    final inOutButtonSize = Size(
      (isPhone ? 110 : 140) * scale,
      (isPhone ? 56 : 68) * scale,
    );
    final inOutTextSize = (isPhone ? 20 : 22) * scale;

    final bool diverIsIn = selectedDiver != null
        ? _diverIsIn(selectedDiver!)
        : false;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn),
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
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryPage(
                                selectedColor: widget.aquacoulisse,
                              ),
                            ),
                          );
                        },
                        child: const Text('History'),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    "${widget.department} - ${widget.aquacoulisse} AQUACOULISSE",
                    style: TextStyle(
                      fontSize: (isPhone ? 28 : 36) * scale,
                      fontWeight: FontWeight.bold,
                      color: getAquacoulisseColor(),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10 * scale),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              // Team buttons only while selecting a diver
                              if (widget.department == "SHOW DIVERS" &&
                                  selectedDiver == null)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 8 * scale),
                                  child: Wrap(
                                    spacing: 6 * scale,
                                    runSpacing: 6 * scale,
                                    children: [
                                      for (final t in teams)
                                        Builder(
                                          builder: (_) {
                                            final bool isSelected =
                                                selectedTeam == t;
                                            final Color selColor = colorForTeam(
                                              t,
                                            );
                                            return ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  selectedTeam = t;
                                                  selectedDiver = null;
                                                  selectedTag = null;
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isSelected
                                                    ? selColor
                                                    : Colors.grey[100],
                                                foregroundColor: isSelected
                                                    ? (t == "WHITE"
                                                          ? Colors.black
                                                          : Colors.white)
                                                    : Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        18 * scale,
                                                      ),
                                                ),
                                                elevation: 0,
                                                minimumSize: Size(
                                                  120 * scale,
                                                  48 * scale,
                                                ),
                                                textStyle: TextStyle(
                                                  fontSize: 14 * scale,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              child: Text(teamDisplay(t)),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              if (selectedDiver == null)
                                Expanded(
                                  child: diversForCurrentTeam.isEmpty
                                      ? Center(
                                          child: Text(
                                            "No divers found.\nAdd in Settings.",
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
                                            for (final diver
                                                in diversForCurrentTeam)
                                              ElevatedButton(
                                                style:
                                                    selectedDiver ==
                                                        diver['name']
                                                    ? colorBtnStyle.copyWith(
                                                        backgroundColor:
                                                            const MaterialStatePropertyAll<
                                                              Color
                                                            >(Colors.green),
                                                      )
                                                    : colorBtnStyle,
                                                onPressed: () {
                                                  setState(() {
                                                    selectedDiver =
                                                        diver['name'];
                                                    selectedTag = null;
                                                    tagPage = 0;
                                                  });
                                                },
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(diver['name']),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              if (selectedDiver != null) ...[
                                Padding(
                                  padding: EdgeInsets.only(bottom: 8 * scale),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
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
                                      if (!diverIsIn) ...[
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
                                                    padding:
                                                        EdgeInsets.symmetric(
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
                                      ] else
                                        const Expanded(
                                          child: SizedBox.shrink(),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: !diverIsIn
                                      ? GridView.count(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: gridSpacing,
                                          crossAxisSpacing: gridSpacing,
                                          childAspectRatio: childAspect,
                                          children: [
                                            for (final t in currentTagPage)
                                              ElevatedButton(
                                                style: selectedTag == t
                                                    ? colorBtnStyle.copyWith(
                                                        backgroundColor:
                                                            MaterialStatePropertyAll<
                                                              Color
                                                            >(
                                                              getAquacoulisseColor(),
                                                            ),
                                                      )
                                                    : neutralBtnStyle,
                                                onPressed: () => setState(
                                                  () => selectedTag = t,
                                                ),
                                                child: Text(
                                                  t.toString().padLeft(2, '0'),
                                                ),
                                              ),
                                          ],
                                        )
                                      : Center(
                                          child: Text(
                                            "Diver is currently IN.\nTap OUT to check out.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize:
                                                  (isPhone ? 16 : 18) * scale,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
                                if (selectedDiver != null &&
                                    selectedTag != null &&
                                    !diverIsIn)
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
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: inOutButtonSize.width,
                                      height: inOutButtonSize.height,
                                      child: ElevatedButton(
                                        onPressed:
                                            (!diverIsIn &&
                                                selectedDiver != null &&
                                                selectedTag != null)
                                            ? _logIn
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
                                        onPressed: selectedDiver != null
                                            ? _logOut
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
  List<Map> divers = [];
  int currentlyIn = 0;
  Timer? _timer;
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    darkMode = Hive.box('prefs').get('darkMode', defaultValue: false);
    _loadDivers();
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

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    divers = List<Map>.from(stored);
    divers.sort(
      (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
        (b['name'] ?? '').toLowerCase(),
      ),
    );
    setState(() {});
  }

  void _addDiver(String name, String department, String? team) {
    if (name.trim().isEmpty) {
      _snack("Diver name can't be empty.");
      return;
    }
    if (divers.any(
      (d) => (d['name'] ?? '').toLowerCase() == name.trim().toLowerCase(),
    )) {
      _snack("Diver already exists.");
      return;
    }
    divers.add({'name': name.trim(), 'department': department, 'team': team});
    divers.sort(
      (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
        (b['name'] ?? '').toLowerCase(),
      ),
    );
    diversBox.put('diversList', divers);
    setState(() {});
    _snack("Diver added!");
  }

  void _removeDiver(String name) {
    divers.removeWhere((d) => d['name'] == name);
    diversBox.put('diversList', divers);
    setState(() {});
    _snack("Diver removed.");
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
                Navigator.pop(ctx);
                _addDiver(newName, selectedDepartment, selectedTeam);
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
              Navigator.pop(context);
              _removeDiver(name);
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

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn),
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
                    child: divers.isEmpty
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
                            itemCount: divers.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = divers[i];
                              String subtitle = d['department'] ?? '';
                              if (d['department'] == "SHOW DIVERS" &&
                                  d['team'] != null) {
                                subtitle += " - ${d['team']}";
                              }
                              return ListTile(
                                title: Text(
                                  d['name'] ?? '',
                                  style: TextStyle(fontSize: 22 * scale),
                                ),
                                subtitle: Text(
                                  subtitle,
                                  style: TextStyle(fontSize: 14 * scale),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 24 * scale,
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

// ===================== HISTORY PAGE (CSV + XML .xls real) ===================
class HistoryPage extends StatefulWidget {
  final String selectedColor;
  const HistoryPage({super.key, required this.selectedColor});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Box logsBox;
  late String colorTab;
  final List<String> colorTabs = ["BLUE", "GREEN", "RED", "WHITE", "ALL"];
  int currentlyIn = 0;
  Timer? _timer;
  late StreamSubscription<BoxEvent> _logsSub;

  @override
  void initState() {
    super.initState();
    logsBox = Hive.box('logs');
    colorTab = widget.selectedColor.toUpperCase();
    if (!colorTabs.contains(colorTab)) colorTab = "ALL";
    _updateCounts();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCounts());
    _logsSub = logsBox.watch().listen((_) {
      if (mounted) setState(() {}); // live updates
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

  List<Map> getLogs() {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    List<Map> logsList = List<Map>.from(logs).reversed.toList();
    if (colorTab != "ALL") {
      logsList = logsList
          .where(
            (log) =>
                (log['aquacoulisse'] ?? '').toString().toUpperCase() ==
                colorTab,
          )
          .toList();
    }

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

    final Map<String, Map> latest = {};
    for (final log in logsList) {
      final k = "${log['name']}|${log['tag']}";
      latest.putIfAbsent(k, () => log);
    }
    final inKeys = latest.entries
        .where((e) => e.value['status'] == 'IN')
        .map((e) => e.key)
        .toSet();

    logsList.sort((a, b) {
      final ka = "${a['name']}|${a['tag']}";
      final kb = "${b['name']}|${b['tag']}";
      final ain = inKeys.contains(ka);
      final bin = inKeys.contains(kb);
      if (ain && !bin) return -1;
      if (!ain && bin) return 1;
      final ad = DateTime.tryParse(a['datetime'] ?? '') ?? DateTime(1970);
      final bd = DateTime.tryParse(b['datetime'] ?? '') ?? DateTime(1970);
      return bd.compareTo(ad);
    });
    return logsList;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final sh = h > 0 ? "${h}h" : "";
    final sm = m > 0 ? "${m}min" : (h == 0 ? "0min" : "");
    return "$sh$sm".trim();
  }

  Color? _tabColor(String tab) {
    switch (tab) {
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

  Color _tabTextColor(String tab, bool selected) {
    if (!selected) return Colors.black;
    if (tab == "WHITE") return Colors.black;
    return Colors.white;
  }

  Widget _tabButton(String tab) {
    final selected = colorTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => colorTab = tab),
        child: Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? _tabColor(tab) : Colors.grey[200],
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? (_tabColor(tab) ?? Colors.grey) : Colors.grey,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            tab,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _tabTextColor(tab, selected),
              letterSpacing: 1.2,
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
    final logs = getLogs();
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
    final dir = await getTemporaryDirectory();
    final fileName = "${_timestampBase()}.csv";
    final file = File("${dir.path}/$fileName");
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: "Dive History CSV Export",
      subject: "Dive History CSV",
    );
  }

  // Create Excel-compatible XML Spreadsheet 2003 (.xls) without external packages
  Future<void> _exportXlsXml() async {
    final logs = getLogs();
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

    final dir = await getTemporaryDirectory();
    final fileName = "${_timestampBase()}.xls";
    final file = File("${dir.path}/$fileName");
    await file.writeAsString(sb.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: "Dive History Excel Export",
      subject: "Dive History XLS",
    );
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

  @override
  Widget build(BuildContext context) {
    final logs = getLogs();
    final isPhone = MediaQuery.of(context).size.width < 600;
    final scale = appScale(context);
    return Scaffold(
      body: Stack(
        children: [
          TopAlert(currentlyIn: currentlyIn),
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
                        'History',
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
                            child: Text('Export CSV & Share'),
                          ),
                          PopupMenuItem(
                            value: 'xls',
                            child: Text('Export Excel (.xls) & Share'),
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
                  Row(children: [for (final t in colorTabs) _tabButton(t)]),
                  SizedBox(height: 16 * scale),
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
                              final diveDur =
                                  (log['status'] == 'OUT' &&
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
                                          fontSize: (isPhone ? 14 : 17) * scale,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        log['status'] ?? "",
                                        style: TextStyle(
                                          fontSize: (isPhone ? 14 : 17) * scale,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        (log['tag'] ?? '').toString(),
                                        style: TextStyle(
                                          fontSize: (isPhone ? 14 : 17) * scale,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: (isPhone ? 14 : 17) * scale,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        diveDur,
                                        style: TextStyle(
                                          fontSize: (isPhone ? 14 : 17) * scale,
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
                                          fontSize: (isPhone ? 14 : 17) * scale,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
