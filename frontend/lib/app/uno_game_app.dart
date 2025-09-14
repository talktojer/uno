import 'package:flutter/material.dart';
import '../config/mobile_theme.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../services/auth_service.dart';

class UNOGameApp extends StatefulWidget {
  const UNOGameApp({super.key});

  @override
  State<UNOGameApp> createState() => _UNOGameAppState();
}

class _UNOGameAppState extends State<UNOGameApp> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AuthService.initialize();
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        title: 'UNO Game',
        theme: MobileTheme.getLightTheme(),
        darkTheme: MobileTheme.getDarkTheme(),
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        debugShowCheckedModeBanner: false,
      );
    }

    return MaterialApp(
      title: 'UNO Game',
      theme: MobileTheme.getLightTheme(),
      darkTheme: MobileTheme.getDarkTheme(),
      themeMode: ThemeMode.system,
      home: AuthService.isLoggedIn ? const HomeScreen() : const LoginScreen(),
      onGenerateRoute: (settings) {
        // Handle game code routes like /ABC12
        if (settings.name != null && settings.name!.length == 5) {
          return MaterialPageRoute(
            builder: (context) => HomeScreen(initialGameCode: settings.name!),
          );
        }
        return null;
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
