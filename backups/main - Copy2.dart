import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

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
  await Hive.openBox('prefs'); // for dark mode
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
    setState(() {
      darkMode = value;
    });
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

// ===================== TOP ALERT (ONLY IF >0) ===============================
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
    _opacity = Tween<double>(begin: 1, end: 0.3).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (_, __) => Opacity(
          opacity: _opacity.value,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("⚠️ ", style: TextStyle(fontSize: 26)),
              Text(
                "${widget.currentlyIn} Divers currently IN !",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== UTIL: CURRENTLY IN COUNT ============================
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (currentlyIn > 0) TopAlert(currentlyIn: currentlyIn),
          Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  const Text(
                    'Choose your department:',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 32,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final dep in departments)
                        ElevatedButton(
                          onPressed: () => _openAquacoulisse(dep),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(260, 70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                            elevation: 0,
                          ),
                          child: Text(dep),
                        ),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            right: 32,
            child: IconButton(
              tooltip: "Settings",
              icon: const Icon(Icons.settings, size: 40),
              onPressed: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== AQUACOULISSE SCREEN =================================
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

  @override
  Widget build(BuildContext context) {
    final colors = ["BLUE", "GREEN", "RED", "WHITE"];
    return Scaffold(
      body: Stack(
        children: [
          if (currentlyIn > 0) TopAlert(currentlyIn: currentlyIn),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.department,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Choose the aquacoulisse:",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 34),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in colors)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: ElevatedButton(
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
                            minimumSize: const Size(150, 80),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                            ),
                            elevation: 0,
                          ),
                          child: Text(c),
                        ),
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
    if (widget.department == "SHOW DIVERS") {
      selectedTeam = teams.first;
    }
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

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = isPhone ? 3 : 5; // unify for all, fits 20
    final aspect = 2.2; // compact

    final colorBtnStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(100, 40),
      backgroundColor: getAquacoulisseColor(),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      textStyle: TextStyle(
        fontSize: isPhone ? 14 : 16,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
    );
    final neutralBtnStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(100, 40),
      backgroundColor: Colors.grey[300],
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      textStyle: TextStyle(
        fontSize: isPhone ? 14 : 16,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
    );

    return Scaffold(
      body: Stack(
        children: [
          if (currentlyIn > 0) TopAlert(currentlyIn: currentlyIn),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(isPhone ? 6 : 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
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
                        child: const Text(
                          'History',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${widget.department} - ${widget.aquacoulisse} AQUACOUILISSE",
                    style: TextStyle(
                      fontSize: isPhone ? 26 : 36,
                      fontWeight: FontWeight.bold,
                      color: getAquacoulisseColor(),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              if (widget.department == "SHOW DIVERS")
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      for (final t in teams)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: ElevatedButton(
                                            onPressed: () {
                                              setState(() {
                                                selectedTeam = t;
                                                selectedDiver = null;
                                                selectedTag = null;
                                              });
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: selectedTeam == t
                                                  ? getAquacoulisseColor()
                                                  : Colors.grey[100],
                                              foregroundColor: selectedTeam == t
                                                  ? Colors.white
                                                  : Colors.black,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              elevation: 0,
                                              minimumSize: const Size(56, 34),
                                              textStyle: TextStyle(
                                                fontSize: isPhone ? 12 : 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            child: Text(t),
                                          ),
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
                                              fontSize: isPhone ? 16 : 20,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        )
                                      : GridView.count(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: aspect,
                                          children: [
                                            for (final diver
                                                in diversForCurrentTeam)
                                              ElevatedButton(
                                                style:
                                                    selectedDiver ==
                                                        diver['name']
                                                    ? colorBtnStyle.copyWith(
                                                        backgroundColor:
                                                            MaterialStateProperty.all(
                                                              Colors.green,
                                                            ),
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
                                                child: Text(diver['name']),
                                              ),
                                          ],
                                        ),
                                ),
                              if (selectedDiver != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      ElevatedButton(
                                        onPressed: _cancel,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red[400],
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(110, 40),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: isPhone ? 14 : 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        child: const Text("Cancel"),
                                      ),
                                      const SizedBox(width: 16),
                                      const Text(
                                        "Tag number:",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
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
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2,
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
                                                              14,
                                                            ),
                                                      ),
                                                      elevation: 0,
                                                      minimumSize: const Size(
                                                        64,
                                                        36,
                                                      ),
                                                      textStyle: TextStyle(
                                                        fontSize: isPhone
                                                            ? 12
                                                            : 14,
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
                                Expanded(
                                  child: GridView.count(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: aspect,
                                    children: [
                                      for (final t in currentTagPage)
                                        ElevatedButton(
                                          style: selectedTag == t
                                              ? colorBtnStyle.copyWith(
                                                  backgroundColor:
                                                      MaterialStateProperty.all(
                                                        getAquacoulisseColor(),
                                                      ),
                                                )
                                              : neutralBtnStyle,
                                          onPressed: () =>
                                              setState(() => selectedTag = t),
                                          child: Text(
                                            t.toString().padLeft(2, '0'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Right side panel
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isPhone ? 10 : 24,
                              horizontal: 8,
                            ),
                            child: Column(
                              children: [
                                if (selectedDiver != null)
                                  Text(
                                    selectedDiver!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isPhone ? 26 : 38,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (selectedDiver != null &&
                                    selectedTag != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      selectedTag!.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: isPhone ? 22 : 34,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: isPhone ? 70 : 100,
                                      height: isPhone ? 40 : 54,
                                      child: ElevatedButton(
                                        onPressed:
                                            (selectedDiver != null &&
                                                selectedTag != null)
                                            ? _logIn
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: isPhone ? 16 : 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        child: const Text("IN"),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    SizedBox(
                                      width: isPhone ? 70 : 100,
                                      height: isPhone ? 40 : 54,
                                      child: ElevatedButton(
                                        onPressed: selectedDiver != null
                                            ? _logOut
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: isPhone ? 16 : 20,
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
    setState(() {
      darkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (currentlyIn > 0) TopAlert(currentlyIn: currentlyIn),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Settings",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Add Diver',
                      style: TextStyle(fontSize: 20),
                    ),
                    onPressed: _showAddDialog,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Dark theme",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: darkMode,
                    onChanged: _toggleDark,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: divers.isEmpty
                        ? const Center(
                            child: Text(
                              "No divers yet.\nTap 'Add Diver' to get started.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: divers.length,
                            separatorBuilder: (_, __) => const Divider(),
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
                                  style: const TextStyle(fontSize: 22),
                                ),
                                subtitle: Text(subtitle),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
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

// ===================== HISTORY PAGE ========================================
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

  @override
  void initState() {
    super.initState();
    logsBox = Hive.box('logs');
    colorTab = widget.selectedColor.toUpperCase();
    if (!colorTabs.contains(colorTab)) colorTab = "ALL";
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
              final diff = outTime.difference(inTime);
              log['diveDuration'] = _formatDuration(diff);
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

  @override
  Widget build(BuildContext context) {
    final logs = getLogs();
    final isPhone = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: Stack(
        children: [
          if (currentlyIn > 0) TopAlert(currentlyIn: currentlyIn),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 8 : 24,
                vertical: isPhone ? 6 : 16,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'History',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [for (final t in colorTabs) _tabButton(t)]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    color: Colors.grey[100],
                    child: Row(
                      children: const [
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Name:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Status:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Tag:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Date and Time:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Dive duration:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Aquacoulisse:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.black54),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(
                            child: Text(
                              "No logs yet.",
                              style: TextStyle(
                                fontSize: 18,
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        log['name'] ?? "",
                                        style: TextStyle(
                                          fontSize: isPhone ? 14 : 17,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        log['status'] ?? "",
                                        style: TextStyle(
                                          fontSize: isPhone ? 14 : 17,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        (log['tag'] ?? '').toString(),
                                        style: TextStyle(
                                          fontSize: isPhone ? 14 : 17,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: isPhone ? 14 : 17,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        diveDur,
                                        style: TextStyle(
                                          fontSize: isPhone ? 14 : 17,
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
                                          fontSize: isPhone ? 14 : 17,
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
