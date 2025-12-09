import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/state_cache.dart';

import 'app.dart';

// Re-export MyApp so existing imports of package:thodw_aqx/main.dart continue to work.
export 'app.dart' show MyApp;

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

  // Initialize Firebase and sign in anonymously so clients can write
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Fallback: initialize with platform defaults if firebase_options is missing for this target
    await Firebase.initializeApp();
  }
  await FirebaseAuth.instance.signInAnonymously();
  // Ensure local boxes exist for legacy reads during migration
  await Hive.initFlutter();
  await Hive.openBox('divers');
  await Hive.openBox('prefs');
  await Hive.openBox('checkins');
  await Hive.openBox('logs');
  // Start Firestore listeners for shared state
  await StateCache.init();
  runApp(const MyApp());
}
