import 'package:flutter/material.dart';
import 'screens/station_list_screen.dart';

void main() {
  runApp(const GapMinderApp());
}

class GapMinderApp extends StatelessWidget {
  const GapMinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Train Times',

      // Define the light theme based on a seed color
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // Define the dark theme based on a seed color
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      // Tell Flutter to automatically follow the device's theme
      themeMode: ThemeMode.system,

      home: const StationListScreen(),
    );
  }
}

