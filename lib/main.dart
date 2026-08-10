import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'helpers/preferences_service.dart';
import 'services/live_activity_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService().init();
  await LiveActivityService().init();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Firebase] Initialization notice: $e');
  }
  runApp(const GapMinderApp());
}

class GapMinderApp extends StatelessWidget {
  const GapMinderApp({super.key});

  static final _defaultLightColorScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent);
  static final _defaultDarkColorScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        return MaterialApp(
          title: 'GapMinder',
          theme: ThemeData(
            colorScheme: lightColorScheme ?? _defaultLightColorScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          home: const SplashScreen(),
        );
      },
    );
  }
}
