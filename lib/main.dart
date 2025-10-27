import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  await Hive.initFlutter();
  await Hive.openBox('divers');
  await Hive.openBox('logs');
  await Hive.openBox('prefs');
  await Hive.openBox('checkins');
  runApp(const MyApp());
}
