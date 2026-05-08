import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_change_screen.dart';
import 'services/admin_service.dart';
import 'services/auth_service.dart';
import 'services/provisioning_service.dart';
import 'services/state_cache.dart';

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
  bool _booting = true;
  User? _firebaseUser;
  AppUserProfile? _profile;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUserProfile?>? _profileSub;

  AppUserProfile? get currentProfile => _profile;
  bool get isAdmin => _profile?.isAdmin == true;

  @override
  void initState() {
    super.initState();
    prefs = Hive.box('prefs');
    darkMode = prefs.get('darkMode', defaultValue: false);
    _authSub = AuthService.authStateChanges().listen(_handleAuthChanged);
  }

  Future<void> _handleAuthChanged(User? user) async {
    await _profileSub?.cancel();
    _profileSub = null;

    if (user == null) {
      if (mounted) {
        setState(() {
          _firebaseUser = null;
          _profile = null;
          _booting = false;
        });
      }
      return;
    }

    if (user.isAnonymous) {
      await AuthService.signOut();
      if (mounted) {
        setState(() {
          _firebaseUser = null;
          _profile = null;
          _booting = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _firebaseUser = user;
        _booting = false;
      });
    }

    try {
      await StateCache.init();
    } catch (_) {}

    _profileSub = AuthService.profileStream(user.uid).listen((profile) async {
      if (mounted) {
        setState(() {
          _firebaseUser = user;
          _profile = profile;
          _booting = false;
        });
      }

      if (profile == null) {
        await AuthService.signOut();
      }
    });
  }

  void toggleDarkMode(bool value) {
    setState(() => darkMode = value);
    prefs.put('darkMode', darkMode);
  }

  Future<void> submitLogin({
    required String melcoId,
    required String password,
  }) async {
    await AuthService.signInWithMelcoId(melcoId: melcoId, password: password);
  }

  Future<void> logout() async {
    await AuthService.signOut();
  }

  Future<void> changePassword(String nextPassword) async {
    await AuthService.changePassword(newPassword: nextPassword);
  }

  Future<ProvisioningResult> createLoginUser({
    required String melcoId,
    required String displayName,
    required String role,
  }) async {
    return AuthService.createLoginUser(
      melcoId: melcoId,
      displayName: displayName,
      role: role,
    );
  }

  Future<List<AdminManagedUser>> listManagedUsers() async {
    return AdminService.listUsers();
  }

  Future<PasswordResetResult> resetManagedUserPassword(String uid) async {
    return AdminService.resetPassword(uid);
  }

  Future<void> setManagedUserDisabled({
    required String uid,
    required bool disabled,
  }) async {
    await AdminService.setDisabled(uid: uid, disabled: disabled);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
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

    Widget home;
    if (_booting) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_firebaseUser == null || _profile == null) {
      home = LoginScreen(onSubmit: submitLogin);
    } else if (_profile!.requirePasswordChange) {
      home = PasswordChangeScreen(
        onSubmit: changePassword,
        onCancel: logout,
        displayName: _profile!.displayName,
      );
    } else {
      home = const HomeScreen();
    }

    return MaterialApp(
      title: 'HODW AQX',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: home,
      debugShowCheckedModeBanner: false,
    );
  }
}
