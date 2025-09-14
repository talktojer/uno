import 'package:flutter/material.dart';
import '../config/mobile_theme.dart';
import '../screens/home_screen.dart';

class UNOGameApp extends StatelessWidget {
  const UNOGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNO Game',
      theme: MobileTheme.getLightTheme(),
      darkTheme: MobileTheme.getDarkTheme(),
      themeMode: ThemeMode
          .system, // Automatically switch between light/dark based on system
      home: const HomeScreen(),
      onGenerateRoute: (settings) {
        // Handle game code routes like /ABC12
        if (settings.name != null && settings.name!.length == 5) {
          return MaterialPageRoute(
            builder: (context) => HomeScreen(initialGameCode: settings.name!),
          );
        }
        return null;
      },
    );
  }
}
