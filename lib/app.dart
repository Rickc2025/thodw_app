import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'screens/force_password_change_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/user_context.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Box _prefs;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _prefs = Hive.box('prefs');
    _darkMode = (_prefs.get('darkMode') ?? _prefs.get('dark_mode') ?? false) ==
        true;
  }

  void toggleDarkMode(bool value) {
    setState(() => _darkMode = value);
    _prefs.put('darkMode', value);
    _prefs.put('dark_mode', value);
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
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: StreamBuilder(
        stream: AuthService.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!snapshot.hasData) {
            UserContext.clear();
            return const LoginScreen();
          }
          return FutureBuilder<bool>(
            future: AuthService.currentUserMustChangePassword(),
            builder: (context, mustChangeSnapshot) {
              if (mustChangeSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (mustChangeSnapshot.data == true) {
                return const ForcePasswordChangeScreen();
              }
              return const HomeScreen();
            },
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
