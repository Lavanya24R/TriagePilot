import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const TriagePilotApp());
}

class TriagePilotApp extends StatelessWidget {
  const TriagePilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TriagePilot',
      theme: AppTheme.theme,
      home: const HomeScreen(),
    );
  }
}