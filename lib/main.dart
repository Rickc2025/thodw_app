import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'services/state_cache.dart';

import 'app.dart';

// Re-export MyApp so existing imports of package:thodw_aqx/main.dart continue to work.
export 'app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

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

  // Initialize Firebase, but don't block the whole app if auth/network/rules fail.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    try {
      // Fallback: initialize with platform defaults if firebase_options is missing for this target
      await Firebase.initializeApp();
    } catch (_) {
      // Keep booting in local-only mode.
    }
  }
  // Ensure local boxes exist for legacy reads during migration
  await Hive.initFlutter();
  await Hive.openBox('divers');
  await Hive.openBox('prefs');
  await Hive.openBox('checkins');
  await Hive.openBox('logs');

  try {
    // Allow local UI to boot; authenticated screens will start listeners after login.
    await StateCache.init();
  } catch (_) {
    // Firestore unavailable or denied; UI can still render and auth can proceed.
  }

  runApp(const MyApp());
}
