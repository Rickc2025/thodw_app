import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THODW AQX',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF8F6FA),
      ),
      home: DepartmentScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// NEW MAIN SCREEN: Department selection
class DepartmentScreen extends StatelessWidget {
  const DepartmentScreen({super.key});

  void _navigateToColor(BuildContext context, String department) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AquacoulisseScreen(department: department),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    const Text(
                      'THODW - AQX',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 32,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final dep in departments)
                          ElevatedButton(
                            onPressed: () => _navigateToColor(context, dep),
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
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.settings, size: 40),
                onPressed: () => _navigateToSettings(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SECOND SCREEN: Aquacoulisse color selection
class AquacoulisseScreen extends StatelessWidget {
  final String department;
  const AquacoulisseScreen({super.key, required this.department});

  void _navigateToNamesTags(BuildContext context, String color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            NamesTagsScreen(department: department, aquacoulisse: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> colors = ["BLUE", "GREEN", "RED", "WHITE"];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                department,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in colors)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: ElevatedButton(
                        onPressed: () => _navigateToNamesTags(context, color),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color == "WHITE"
                              ? Colors.grey
                              : color == "BLUE"
                              ? Colors.blue
                              : color == "GREEN"
                              ? Colors.green
                              : Colors.red,
                          foregroundColor: color == "WHITE"
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
                        child: Text(color),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// THIRD SCREEN: Names/Tags/IN-OUT
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const int tagsPerPage = 20;

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    logsBox = Hive.box('logs');
    _loadDivers();
    if (widget.department == "SHOW DIVERS") {
      selectedTeam = teams[0];
    }
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    final list = List<Map>.from(stored);
    setState(() {
      divers = list.where((d) {
        if (widget.department == "SHOW DIVERS") {
          return d['department'] == "SHOW DIVERS";
        } else {
          return d['department'] == widget.department;
        }
      }).toList();
    });
  }

  List<Map> get diversForCurrentTeam {
    if (widget.department == "SHOW DIVERS") {
      return divers.where((d) => d['team'] == selectedTeam).toList();
    } else {
      return divers;
    }
  }

  List<int> get currentTagPage {
    final start = tagPage * tagsPerPage + 1;
    final end = (tagPage + 1) * tagsPerPage + 1;
    return List.generate(
      tagsPerPage,
      (i) => start + i,
    ).where((n) => n <= 100).toList();
  }

  int get maxTagPage => (100 / tagsPerPage).ceil();

  Future<void> _playConfirmSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/pling.mp3'));
    } catch (_) {}
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
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

  void _logIn() async {
    if (selectedDiver == null) return;
    if (selectedTag == null) {
      _showSnack("Please select a tag number.");
      return;
    }
    if (_diverIsIn(selectedDiver!)) {
      _showSnack("Diver already IN.");
      return;
    }
    final log = {
      'name': selectedDiver!,
      'status': 'IN',
      'tag': selectedTag!,
      'datetime': DateTime.now().toIso8601String(),
      'aquacoulisse': widget.aquacoulisse,
    };
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    logs.add(log);
    logsBox.put('logsList', logs);
    _showSnack("Diver checked IN.");
    await _playConfirmSound();
    setState(() {
      selectedDiver = null;
      selectedTag = null;
    });
  }

  void _logOut() async {
    if (selectedDiver == null) return;
    if (!_diverIsIn(selectedDiver!)) {
      _showSnack("Diver already OUT.");
      return;
    }
    final lastInTag = _diverLastInTag(selectedDiver!);
    final log = {
      'name': selectedDiver!,
      'status': 'OUT',
      'tag': lastInTag ?? '',
      'datetime': DateTime.now().toIso8601String(),
      'aquacoulisse': widget.aquacoulisse,
    };
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    logs.add(log);
    logsBox.put('logsList', logs);
    _showSnack("Diver checked OUT.");
    await _playConfirmSound();
    setState(() {
      selectedDiver = null;
      selectedTag = null;
    });
  }

  bool _diverIsIn(String diver) {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    final logsList = List<Map>.from(logs);
    final diverLogs = logsList.where((log) => log['name'] == diver).toList();
    if (diverLogs.isEmpty) return false;
    return diverLogs.last['status'] == 'IN';
  }

  int? _diverLastInTag(String diver) {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    final logsList = List<Map>.from(logs).reversed;
    for (final log in logsList) {
      if (log['name'] == diver && log['status'] == 'IN') {
        return log['tag'];
      }
    }
    return null;
  }

  void _cancelSelection() {
    setState(() {
      selectedDiver = null;
      selectedTag = null;
      tagPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = widget.department == "SHOW DIVERS"
        ? 2
        : (isPhone ? 2 : 4); // Show Divers always max 2 columns

    final colorButtonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(120, 40),
      backgroundColor: getAquacoulisseColor(),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      textStyle: TextStyle(
        fontSize: isPhone ? 16 : 18,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
    );
    final neutralButtonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(120, 40),
      backgroundColor: Colors.grey[300],
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      textStyle: TextStyle(
        fontSize: isPhone ? 16 : 18,
        fontWeight: FontWeight.bold,
      ),
      elevation: 0,
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isPhone ? 6.0 : 12.0),
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
                          builder: (context) =>
                              HistoryPage(selectedColor: widget.aquacoulisse),
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
              const SizedBox(height: 2),
              Text(
                '${widget.department} - ${widget.aquacoulisse} AQUACOUILISSE',
                style: TextStyle(
                  fontSize: isPhone ? 26 : 38,
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.department == "SHOW DIVERS") ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Row(
                                children: [
                                  for (final team in teams)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0,
                                      ),
                                      child: ElevatedButton(
                                        onPressed: () => setState(() {
                                          selectedTeam = team;
                                          selectedDiver = null;
                                          selectedTag = null;
                                        }),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: selectedTeam == team
                                              ? getAquacoulisseColor()
                                              : Colors.grey[100],
                                          foregroundColor: selectedTeam == team
                                              ? Colors.white
                                              : Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          minimumSize: const Size(60, 34),
                                          elevation: 0,
                                          textStyle: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: isPhone ? 14 : 15,
                                          ),
                                        ),
                                        child: Text(
                                          team,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (selectedDiver == null)
                            Expanded(
                              child: diversForCurrentTeam.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No divers found.\nPlease add divers in Settings.",
                                        style: TextStyle(
                                          fontSize: isPhone ? 16 : 22,
                                          color: Colors.grey[600],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : GridView.count(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      shrinkWrap: true,
                                      childAspectRatio: 2.7,
                                      children: [
                                        for (final diver
                                            in diversForCurrentTeam)
                                          ElevatedButton(
                                            style:
                                                selectedDiver == diver['name']
                                                ? colorButtonStyle.copyWith(
                                                    backgroundColor:
                                                        WidgetStateProperty.all(
                                                          Colors.green,
                                                        ),
                                                  )
                                                : colorButtonStyle,
                                            onPressed: () => setState(() {
                                              selectedDiver = diver['name'];
                                              selectedTag = null;
                                              tagPage = 0;
                                            }),
                                            child: Text(diver['name']),
                                          ),
                                      ],
                                    ),
                            ),
                          if (selectedDiver != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[400],
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(110, 40),
                                      textStyle: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: isPhone ? 14 : 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                    ),
                                    onPressed: _cancelSelection,
                                    child: const Text("Cancel"),
                                  ),
                                  const SizedBox(width: 18),
                                  const Text(
                                    "Tag number:",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  // Tag page selector row (horizontal tabs)
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (int i = 0; i < maxTagPage; i++)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2.0,
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
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  minimumSize: const Size(
                                                    60,
                                                    34,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 0,
                                                      ),
                                                  elevation: 0,
                                                  textStyle: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: isPhone ? 13 : 15,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                                child: Text(
                                                  "${(i * tagsPerPage + 1).toString().padLeft(2, '0')}-${((i + 1) * tagsPerPage).clamp(1, 100).toString().padLeft(2, '0')}",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: tagPage == i
                                                        ? Colors.white
                                                        : Colors.black,
                                                  ),
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
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                shrinkWrap: true,
                                childAspectRatio: 2.7,
                                children: [
                                  for (final tag in currentTagPage)
                                    ElevatedButton(
                                      style: selectedTag == tag
                                          ? colorButtonStyle.copyWith(
                                              backgroundColor:
                                                  WidgetStateProperty.all(
                                                    getAquacoulisseColor(),
                                                  ),
                                            )
                                          : neutralButtonStyle,
                                      onPressed: () =>
                                          setState(() => selectedTag = tag),
                                      child: Text(
                                        tag.toString().padLeft(2, '0'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: EdgeInsets.symmetric(
                          vertical: isPhone ? 12 : 24,
                          horizontal: 8,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (selectedDiver != null)
                              Text(
                                selectedDiver!,
                                style: TextStyle(
                                  fontSize: isPhone ? 27 : 40,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (selectedDiver != null && selectedTag != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10.0),
                                child: Text(
                                  selectedTag!.toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    fontSize: isPhone ? 20 : 32,
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
                                  height: isPhone ? 36 : 50,
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
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      textStyle: TextStyle(
                                        fontSize: isPhone ? 16 : 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    child: const Text("IN"),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: isPhone ? 70 : 100,
                                  height: isPhone ? 36 : 50,
                                  child: ElevatedButton(
                                    onPressed: selectedDiver != null
                                        ? _logOut
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      textStyle: TextStyle(
                                        fontSize: isPhone ? 16 : 22,
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
    );
  }
}

// Settings page, now asks for department/team when adding a diver
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Box diversBox;
  List<Map> divers = [];

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    _loadDivers();
  }

  void _loadDivers() {
    final stored = diversBox.get('diversList', defaultValue: <Map>[]);
    setState(() {
      divers = List<Map>.from(stored);
      divers.sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase(),
        ),
      );
    });
  }

  void _addDiver(String name, String department, String? team) {
    if (name.trim().isEmpty) {
      _showSnackBar("Diver name can't be empty.");
      return;
    }
    if (divers.any(
      (d) => (d['name'] ?? '').toLowerCase() == name.trim().toLowerCase(),
    )) {
      _showSnackBar("Diver already exists.");
      return;
    }
    setState(() {
      divers.add({'name': name.trim(), 'department': department, 'team': team});
      divers.sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase(),
        ),
      );
      diversBox.put('diversList', divers);
    });
    _showSnackBar("Diver added!");
  }

  void _removeDiver(String name) {
    setState(() {
      divers.removeWhere((d) => d['name'] == name);
      diversBox.put('diversList', divers);
    });
    _showSnackBar("Diver removed.");
  }

  void _showAddDialog() {
    String newName = '';
    String selectedDepartment = departments[0];
    String? selectedTeam = teams[0];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
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
                    onChanged: (value) => newName = value,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: selectedDepartment,
                    items: [
                      for (final dep in departments)
                        DropdownMenuItem(value: dep, child: Text(dep)),
                    ],
                    onChanged: (dep) {
                      setStateDialog(() {
                        selectedDepartment = dep!;
                        if (selectedDepartment == "SHOW DIVERS" &&
                            selectedTeam == null) {
                          selectedTeam = teams[0];
                        } else if (selectedDepartment != "SHOW DIVERS") {
                          selectedTeam = null;
                        }
                      });
                    },
                  ),
                  if (selectedDepartment == "SHOW DIVERS") ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Team',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: selectedTeam,
                      items: [
                        for (final t in teams)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (t) => setStateDialog(() => selectedTeam = t),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Add'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _addDiver(newName, selectedDepartment, selectedTeam);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRemoveDialog(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Diver"),
        content: Text("Are you sure you want to remove '$name'?"),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Remove'),
            onPressed: () {
              Navigator.of(context).pop();
              _removeDiver(name);
            },
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Diver', style: TextStyle(fontSize: 20)),
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
            const SizedBox(height: 24),
            Expanded(
              child: divers.isEmpty
                  ? const Center(
                      child: Text(
                        "No divers yet.\nTap 'Add Diver' to get started.",
                        style: TextStyle(fontSize: 20, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: divers.length,
                      separatorBuilder: (context, idx) => const Divider(),
                      itemBuilder: (context, idx) {
                        final diver = divers[idx];
                        String subtitle = diver['department'] ?? '';
                        if (diver['department'] == "SHOW DIVERS" &&
                            diver['team'] != null) {
                          subtitle += " - ${diver['team']}";
                        }
                        return ListTile(
                          title: Text(
                            diver['name'] ?? '',
                            style: const TextStyle(fontSize: 22),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: const TextStyle(fontSize: 15),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _showRemoveDialog(diver['name']),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// HISTORY PAGE (full)
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

  @override
  void initState() {
    super.initState();
    logsBox = Hive.box('logs');
    colorTab = widget.selectedColor.toUpperCase();
    if (!colorTabs.contains(colorTab)) colorTab = "ALL";
  }

  List<Map> getLogs() {
    final logs = logsBox.get('logsList', defaultValue: <Map>[]);
    List<Map> logsList = List<Map>.from(logs);
    logsList = logsList.reversed.toList();
    if (colorTab != "ALL") {
      logsList = logsList
          .where(
            (log) =>
                (log['aquacoulisse'] ?? '').toString().toUpperCase() ==
                colorTab,
          )
          .toList();
    }

    // Pair IN/OUT logs by diver and tag, ignoring color
    Map<String, Map> lastIN = {};
    for (int i = logsList.length - 1; i >= 0; i--) {
      final log = logsList[i];
      if (log['status'] == 'IN') {
        final key = '${log['name'] ?? ''}|${log['tag'] ?? ''}';
        lastIN[key] = log;
      }
      if (log['status'] == 'OUT') {
        final key = '${log['name'] ?? ''}|${log['tag'] ?? ''}';
        if (lastIN.containsKey(key)) {
          final inLog = lastIN[key]!;
          try {
            DateTime inTime = DateTime.parse(inLog['datetime'] ?? "");
            DateTime outTime = DateTime.parse(log['datetime'] ?? "");
            if (outTime.isAfter(inTime)) {
              final diff = outTime.difference(inTime);
              log['diveDuration'] = _formatDuration(diff);
              lastIN.remove(key);
            }
          } catch (_) {}
        }
      }
    }

    // Show currently IN divers' logs at top based on latest log (regardless of color)
    Map<String, Map> lastLogByDiverTag = {};
    for (var log in logsList) {
      final diver = (log['name'] ?? '').toString();
      final tag = (log['tag'] ?? '').toString();
      final key = '$diver|$tag';
      if (!lastLogByDiverTag.containsKey(key)) {
        lastLogByDiverTag[key] = log;
      }
    }
    Set<String> currentlyInKeys = lastLogByDiverTag.entries
        .where((e) => (e.value['status'] ?? '') == 'IN')
        .map((e) => e.key)
        .toSet();

    logsList.sort((a, b) {
      String ak = '${a['name'] ?? ''}|${a['tag'] ?? ''}';
      String bk = '${b['name'] ?? ''}|${b['tag'] ?? ''}';
      bool ain = currentlyInKeys.contains(ak);
      bool bin = currentlyInKeys.contains(bk);
      if (ain && !bin) return -1;
      if (!ain && bin) return 1;
      final adt = DateTime.tryParse(a['datetime'] ?? "") ?? DateTime(1970);
      final bdt = DateTime.tryParse(b['datetime'] ?? "") ?? DateTime(1970);
      return bdt.compareTo(adt);
    });

    return logsList;
  }

  String _formatDuration(Duration d) {
    int hours = d.inHours;
    int mins = d.inMinutes.remainder(60);
    String h = hours > 0 ? "${hours}h" : "";
    String m = mins > 0 ? "${mins}min" : (hours == 0 ? "0min" : "");
    return "$h$m".trim();
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
    final bool selected = colorTab == tab;
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
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isPhone ? 8.0 : 24.0,
            vertical: isPhone ? 7 : 16,
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
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 10),
              Row(children: [for (final tab in colorTabs) _tabButton(tab)]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final log = logs[idx];
                          DateTime? dt;
                          try {
                            dt = DateTime.parse(log['datetime'] ?? "");
                          } catch (_) {}
                          final formattedDate = dt == null
                              ? ""
                              : "${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")} ${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}";
                          final diveDuration =
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
                                    log['tag']?.toString() ?? "",
                                    style: TextStyle(
                                      fontSize: isPhone ? 14 : 17,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: isPhone ? 14 : 17,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    diveDuration,
                                    style: TextStyle(
                                      fontSize: isPhone ? 14 : 17,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    (log['aquacoulisse'] ?? "")
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
    );
  }
}
