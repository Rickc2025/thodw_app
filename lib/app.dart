import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'screens/home_screen.dart';

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
